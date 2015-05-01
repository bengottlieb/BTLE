//
//  BTLEPeripheral.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth
import SA_Swift

let rssi_range_touching = -25
let rssi_range_very_close = -30
let rssi_range_close = -35
let rssi_range_nearby = -45
let rssi_range_same_room = -55
let rssi_range_around = -65


protocol BTLEPeripheralProtocol {
	init();
	init(peripheral: CBPeripheral, RSSI: BTLEPeripheral.RSSValue?, advertisementData adv: [NSObject: AnyObject]?);
}

public struct BTLEServiceUUIDs {
	public static let deviceInfo = CBUUID(string: "0x180A")
	
	public static let iOSContinuity = CBUUID(string: "D0611E78-BBB4-4591-A5F8-487910AE4366")

	public static let battery = CBUUID(string: "180F")
	public static let currentTime = CBUUID(string: "1805")
	public static let alert = CBUUID(string: "1811")
	public static let running = CBUUID(string: "1814")
	public static let userData = CBUUID(string: "181C")
	public static let generic = CBUUID(string: "1801")
	public static let genericAccess = CBUUID(string: "1800")


}

public struct BTLECharacteristicUUIDs {
	public static let serialNumber = CBUUID(string: "0x2A25")
	public static let modelNumber = CBUUID(string: "0x2A24")
	public static let firmwareVersion = CBUUID(string: "0x2A26")
	public static let hardwareRevision = CBUUID(string: "0x2A27")
	public static let softwareRevision = CBUUID(string: "0x2A28")
	public static let manufacturersName = CBUUID(string: "0x2A29")
	public static let regulatoryCertificationData = CBUUID(string: "0x2A2A")
	public static let pnpID = CBUUID(string: "0x2A50")
}



public class BTLEPeripheral: NSObject, CBPeripheralDelegate, Printable {
	deinit {
		println("deiniting: \(self)")
	}
	public enum State { case Discovered, Connecting, Connected, Disconnecting, Undiscovered, Unknown }
	public typealias RSSValue = Int
	public enum Distance { case Touching, VeryClose, Close, Nearby, SameRoom, Around, Far, Unknown
		init(raw: RSSValue) {
			if raw > rssi_range_touching { self = .Touching }
			else if raw > rssi_range_very_close { self = .VeryClose }
			else if raw > rssi_range_close { self = .Close }
			else if raw > rssi_range_nearby { self = .Nearby }
			else if raw > rssi_range_same_room { self = .SameRoom }
			else if raw > rssi_range_around { self = .Around }
			else { self = .Far }
		}
		
		var toString: String {
			switch self {
			case .Touching: return "touching"
			case .VeryClose: return "very close"
			case .Close: return "close"
			case .Nearby: return "nearby"
			case .SameRoom: return "same room"
			case .Around: return "around"
			case .Far: return "far"
			case .Unknown: return "unknown"
			}
		}
	}
	
	public var cbPeripheral: CBPeripheral!
	public var uuid: NSUUID!
	public var name: String!
	public var lastCommunicatedAt = NSDate() { didSet {
		if self.state == .Undiscovered {
			self.state = .Discovered
			self.sendNotification(BTLE.notifications.peripheralDidRegainComms)
		}
		self.updateVisibilityTimer()
	}}
	public var loadingState = BTLE.LoadingState.NotLoaded {
		didSet {
			if self.loadingState == .Loaded {
				self.sendNotification(BTLE.notifications.peripheralDidFinishLoading)
				if BTLE.debugLevel > DebugLevel.Low { println("Loaded device: \(self.fullDescription)") }
			}
		}
	}
	public var services: [BTLEService] = []
	public var advertisementData: [NSObject: AnyObject] = [:] { didSet {
		self.sendNotification(BTLE.notifications.peripheralDidUpdateAdvertisementData)
	}}
	public var state: State = .Discovered { didSet {
		switch self.state {
		case .Connected:
			self.updateRSSI()
			self.reloadServices()
			
			
		case .Disconnecting: fallthrough
		case .Discovered:
			self.cancelLoad()
			
		case .Undiscovered:
			self.disconnect()
			
		default: break
		}
	}}
	public var rssi: RSSValue? { didSet {
		self.lastCommunicatedAt = NSDate()
		self.sendNotification(BTLE.notifications.peripheralDidUpdateRSSI)
	}}
	public var rawRSSI: RSSValue?
	
	public var distance: Distance { if let rssi = self.rssi { return Distance(raw: rssi) }; return .Unknown }
	
	public var rssiHistory: [RSSValue] = []
	func setCurrentRSSI(newRSSI: RSSValue) {
		if abs(newRSSI) == 127 { return }
		
		self.rawRSSI = newRSSI
		if BTLE.manager.disableRSSISmoothing {
			self.rssi = newRSSI
		} else {
			self.rssiHistory.append(newRSSI)
			if self.rssiHistory.count > 10 { self.rssiHistory.removeAtIndex(0) }
			
			self.rssi = self.rssiHistory.reduce(0, combine: +) / self.rssiHistory.count
		}
		self.lastCommunicatedAt = NSDate()
	}
	
	public override required init() {
		super.init()
	}
	
	public required init(peripheral: CBPeripheral, RSSI: RSSValue?, advertisementData adv: [NSObject: AnyObject]?) {
		if BTLE.debugLevel == .High { println("creating peripheral from \(peripheral)") }
		cbPeripheral = peripheral
		uuid = peripheral.identifier
		name = peripheral.name ?? "unknown"
		if let adv = adv { advertisementData = adv }
		
		ignored = BTLE.manager.scanner.ignoredPeripheralUUIDs.contains(peripheral.identifier.UUIDString)
		if ignored && BTLE.debugLevel > DebugLevel.Low { println("Ignoring peripheral: \(name), \(uuid)") }
		super.init()
		peripheral.delegate = self
		peripheral.readRSSI()
		self.rssi = RSSI
		self.updateVisibilityTimer()
		
	}
	
	public func connect() {
		self.state = .Connecting
		BTLE.manager.scanner.cbCentral.connectPeripheral(self.cbPeripheral, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
	}
	
	public func disconnect() {
		if self.state == .Connected { self.state = .Disconnecting }
		
		BTLE.manager.scanner.cbCentral?.cancelPeripheralConnection(self.cbPeripheral)
	}
	
	func cancelLoad() {
		if self.loadingState == .Loading { self.loadingState = .LoadingCancelled }
		
		for svc in self.services { svc.cancelLoad() }
	}
	
	public var ignored: Bool = false {
		didSet {
			if self.ignored {
				BTLE.manager.scanner.addIgnoredPeripheral(self)
			} else {
				BTLE.manager.scanner.removeIgnoredPeripheral(self)
			}
			
		}
	}
	
	public var summaryDescription: String {
		var string = ""
		if self.state == .Connected { string = "Connected " + string }
		if self.state == .Connecting { string = "Connecting " + string }
		
		switch self.loadingState {
		case .NotLoaded: break
		case .Loading: string = "Loading " + string
		case .Loaded: string = "Loaded " + string
		case .LoadingCancelled: string = "Cancelled " + string
		case .Reloading: string = "Reloading " + string
		}
		
		return string
	}

	public var fullDescription: String {
		var desc = "\(self.summaryDescription)\n\(self.advertisementData)"
		
		for svc in self.services {
			desc = desc + "\n" + svc.fullDescription
		}
		
		return desc
	}
	
	public func updateRSSI() {
		self.cbPeripheral.readRSSI()
	}
	
	public func serviceWithUUID(uuid: CBUUID) -> BTLEService? { return filter(self.services, { $0.cbService.UUID == uuid }).last }
	public func characteristicFromCBCharacteristic(characteristic: CBCharacteristic) -> BTLECharacteristic? {
		if let service = self.serviceWithUUID(characteristic.service.UUID) {
			if let chr = service.characteristicWithUUID(characteristic.UUID) {
				return chr
			}
		}
		return nil
	}
	
	public func reloadServices() {
		//self.loadServices(self.services)
		self.services = []
		self.cbPeripheral.discoverServices(nil)
	}
	
	//=============================================================================================
	//MARK: Internal
	func loadServices(services: [BTLEService]) {
		self.sendNotification(BTLE.notifications.peripheralDidBeginLoading)
		self.loadingState = .Loading
		for service in services {
			service.reload()
		}
	}
	
	func didFinishLoadingService(service: BTLEService) {
		println("Finished loading \(service.uuid), \(self.numberOfLoadingServices) left")
		if self.numberOfLoadingServices == 0 {
			self.loadingState = .Loaded
		}
	}
	
	var numberOfLoadingServices: Int {
		var count = 0
		
		for chr in self.services {
			if chr.loadingState == .Loading || chr.loadingState == .Reloading { count++ }
		}
		return count
	}

	func findOrCreateService(cbService: CBService) -> BTLEService {
		if let service = self.serviceWithUUID(cbService.UUID) {
			return service
		}
		
		var service = BTLEService.createService(service: cbService, onPeriperhal: self)
		self.services.append(service)

		return service
	}
	
	//=============================================================================================
	//MARK: Timeout

	weak var visibilityTimer: NSTimer?
	func updateVisibilityTimer() -> NSTimer? {
		self.visibilityTimer?.invalidate()
		self.visibilityTimer = nil
		
		if self.state == .Discovered && BTLE.manager.deviceLifetime > 0 {
			dispatch_async_main {
				var timeSinceLastComms = abs(self.lastCommunicatedAt.timeIntervalSinceNow)
				var a = abs(timeSinceLastComms)
				if BTLE.manager.deviceLifetime > timeSinceLastComms {
					var timeoutInverval = (BTLE.manager.deviceLifetime - timeSinceLastComms)
					
					// if timeoutInverval < 3 { println("short term timer: \(timeSinceLastComms) sec") }
					
					self.visibilityTimer?.invalidate()
					self.visibilityTimer = NSTimer.scheduledTimerWithTimeInterval(timeoutInverval, target: self, selector: "disconnectDueToTimeout", userInfo: nil, repeats: false)
				} else if BTLE.manager.deviceLifetime > 0 {
					self.disconnectDueToTimeout()
				}
			}
		}
		
		return nil
	}
	
	func disconnectDueToTimeout() {
		self.visibilityTimer?.invalidate()
		self.visibilityTimer = nil
		
		if self.state == .Discovered {
			self.state = .Undiscovered
			self.sendNotification(BTLE.notifications.peripheralDidLoseComms)
		}
	}
	
	func sendNotification(name: String) {
		if !self.ignored { NSNotification.postNotification(name, object: self) }
	}

	//=============================================================================================
	//MARK: Delegate - Peripheral
	
	public func peripheral(peripheral: CBPeripheral!, didReadRSSI RSSI: NSNumber!, error: NSError!) {
		if let rssi = RSSI {
			self.rssi = rssi.integerValue
		}
	}

	public func peripheralDidUpdateName(peripheral: CBPeripheral!) {
		self.name = peripheral.name
		self.sendNotification(BTLE.notifications.peripheralDidUpdateName)
		if BTLE.debugLevel > DebugLevel.Low { println("Updated name for: \(self.name)") }
	}

	//=============================================================================================
	//MARK: Delegate - Service
	public func peripheral(peripheral: CBPeripheral!, didModifyServices invalidatedServices: [AnyObject]!) {
		var remainingServices = self.services
		
		for invalidated in invalidatedServices as! [CBService] {
			if self.shouldLoadService(invalidated) {
				self.findOrCreateService(invalidated).reload()
			}
		}
	}
	
	public func peripheral(peripheral: CBPeripheral!, didDiscoverServices error: NSError!) {
		if let services = self.cbPeripheral.services as? [CBService] {
			for svc in services {
				if self.shouldLoadService(svc) {
					self.findOrCreateService(svc)
				}
			}
			
			if self.numberOfLoadingServices == 0 {
				self.loadingState = .Loaded
			}
		}
	}

	
	//=============================================================================================
	//MARK:	 Delegate - Characteristic

	public func peripheral(peripheral: CBPeripheral!, didDiscoverCharacteristicsForService service: CBService!, error: NSError!) {
		if self.shouldLoadService(service) {
			self.findOrCreateService(service).updateCharacteristics()
		}
	}
	
	public func peripheral(peripheral: CBPeripheral!, didUpdateValueForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
		if self.shouldLoadService(characteristic.service) {
			self.findOrCreateService(characteristic.service).didLoadCharacteristic(characteristic, error: error)
		}
	}
	
	public func peripheral(peripheral: CBPeripheral!, didWriteValueForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
		self.characteristicFromCBCharacteristic(characteristic)?.didWriteValue(error)
	}
	
	public func peripheral(peripheral: CBPeripheral!, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
		self.characteristicFromCBCharacteristic(characteristic)?.didUpdateNotifyValue()
	}
	
	public func peripheral(peripheral: CBPeripheral!, didDiscoverDescriptorsForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
		self.characteristicFromCBCharacteristic(characteristic)?.loadDescriptors()
	}
	
	public func peripheral(peripheral: CBPeripheral!, didUpdateValueForDescriptor descriptor: CBDescriptor!, error: NSError!) {
		self.characteristicFromCBCharacteristic(descriptor.characteristic)?.didUpdateValueForDescriptor(descriptor)
	}
	
	public func peripheral(peripheral: CBPeripheral!, didWriteValueForDescriptor descriptor: CBDescriptor!, error: NSError!) {
		self.characteristicFromCBCharacteristic(descriptor.characteristic)?.didWriteValueForDescriptor(descriptor)
	}
	
	//=============================================================================================
	//MARK: For overriding

	
	public func shouldLoadService(service: CBService) -> Bool {
		return true
	}
}

