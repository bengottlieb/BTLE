//
//  BTLEPeripheral.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

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



public class BTLEPeripheral: NSObject, CBPeripheralDelegate {
	deinit {
		BTLE.debugLog(.SuperHigh, "BTLE Peripheral: deiniting: \(self)")
	}
	public enum Ignored: Int { case Not, BlackList, MissingServices, CheckingForServices }
	public enum State { case Discovered, Connecting, Connected, Disconnecting, Undiscovered, Unknown
		var description: String {
			switch self {
			case .Discovered: return "Discovered"
			case .Connecting: return "Discovered"
			case .Connected: return "Connected"
			case .Disconnecting: return "Disconnecting"
			case .Undiscovered: return "Undiscovered"
			case .Unknown: return "Unknown"
			}
		}
	}
	public typealias RSSValue = Int
	public enum Distance: Int { case Touching, VeryClose, Close, Nearby, SameRoom, Around, Far, Unknown
		init(raw: RSSValue) {
			if raw > rssi_range_touching { self = .Touching }
			else if raw > rssi_range_very_close { self = .VeryClose }
			else if raw > rssi_range_close { self = .Close }
			else if raw > rssi_range_nearby { self = .Nearby }
			else if raw > rssi_range_same_room { self = .SameRoom }
			else if raw > rssi_range_around { self = .Around }
			else { self = .Far }
		}
		
		public var toString: String {
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

		public var toFloat: Float {
			switch self {
			case .Touching: return 0.0
			case .VeryClose: return 0.1
			case .Close: return 0.25
			case .Nearby: return 0.4
			case .SameRoom: return 0.5
			case .Around: return 0.75
			case .Far: return 0.9
			case .Unknown: return 1.0
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
		btle_delay(0.001) { self.updateVisibilityTimer() }
	}}
	public var loadingState = BTLE.LoadingState.NotLoaded {
		didSet {
			if self.loadingState == .Loaded {
				self.sendNotification(BTLE.notifications.peripheralDidFinishLoading)
				BTLE.debugLog(.Medium, "BTLE Peripheral: Loaded: \(self.fullDescription)")
				self.sendConnectionCompletions(nil)
			}
		}
	}
	public var services: [BTLEService] = []
	public var advertisementData: [NSObject: AnyObject] = [:] { didSet {
		self.sendNotification(BTLE.notifications.peripheralDidUpdateAdvertisementData)
	}}
	
	func didFailToConnect(error: NSError?) {
		BTLE.debugLog(.Medium, "Failed to connect \(self.name): \(error)")
		self.sendConnectionCompletions(error)
	}
	
	func sendConnectionCompletions(error: NSError?) {
		BTLE.debugLog(.Medium, "Sending \(self.connectionCompletionBlocks.count) completion messages (\(error))")
		let completions = self.connectionCompletionBlocks
		self.connectionCompletionBlocks = []
		
		for block in completions {
			block(error)
		}
	}
	
	public var state: State = .Discovered { didSet {
		if self.state == oldValue { return }
	
		BTLE.debugLog(.Medium, "Changing state on \(self.name), \(oldValue.description) -> \(self.state.description)")
	
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
		BTLE.debugLog(.High, "Peripheral: creating from \(peripheral)")
		cbPeripheral = peripheral
		uuid = peripheral.identifier
		name = peripheral.name ?? "unknown"
		if let adv = adv { advertisementData = adv }
		
		super.init()

		peripheral.delegate = self
		peripheral.readRSSI()
		self.rssi = RSSI
		self.updateVisibilityTimer()

		if BTLE.scanner.ignoredPeripheralUUIDs.contains(peripheral.identifier.UUIDString) {
			ignored = .BlackList
			BTLE.debugLog(.Medium, "Peripheral: Ignoring: \(name), \(uuid)")
		} else if BTLE.manager.services.count > 0 {
			if BTLE.manager.serviceFilter == .AdvertisingData {
				if let info = adv {
					self.updateIgnoredWithAdvertisingData(info)
				} else {
					self.ignored = .MissingServices
				}
			} else if BTLE.manager.serviceFilter == .ActualServices {
				self.ignored = .CheckingForServices
				self.connect()
			}
		}
		
		if self.ignored == .Not {
			BTLE.debugLog(.Medium, "BTLE Peripheral: not ignored: \(self)")
		}
	}
	
	func updateIgnoredWithAdvertisingData(info: [NSObject: AnyObject]) {
		if BTLE.manager.serviceFilter == .AdvertisingData && BTLE.manager.services.count > 0 {
			var ignored = true
			if let services = info[CBAdvertisementDataServiceUUIDsKey] as? NSArray {
				for service in services {
					if let cbid = service as? CBUUID {
						if BTLE.manager.services.contains(cbid) { ignored = false; break }
					}
				}
			}
			if ignored {
				self.ignored = .MissingServices
				BTLE.debugLog(.SuperHigh, "BTLE Peripheral: ignored \(self.cbPeripheral.name) with advertising info: \(info)")
			} else {
				self.ignored = .Not
			}
		}
	}
	
	public func ignore(ignore: Ignored = .BlackList) {
		self.ignored = ignore
	}
	
	var connectionCompletionBlocks: [(NSError?) -> Void] = []
	
	public func connect(reloadServices: Bool = false, completion: ((NSError?) -> ())? = nil) {
		BTLE.debugLog(.Medium, "Attempting to connect to \(self.name), current state: \(self.state.description)")
		if let completion = completion { self.connectionCompletionBlocks.append(completion) }
		switch self.state {
		case .Connecting:
			break
			
		case .Connected:
			self.sendConnectionCompletions(nil)
			
		case .Discovered: fallthrough
		case .Disconnecting: fallthrough
		case .Undiscovered: fallthrough
		case .Unknown:
			if (reloadServices) { self.loadingState = .Reloading }
			self.state = .Connecting
			BTLE.scanner.cbCentral.connectPeripheral(self.cbPeripheral, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
		}
	}
	
	public func disconnect() {
		BTLE.debugLog(.Medium, "Disconnecting from \(self.name), current state: \(self.state.description)")
		if self.state == .Connected { self.state = .Disconnecting }
		
		BTLE.scanner.cbCentral?.cancelPeripheralConnection(self.cbPeripheral)
	}
	
	func cancelLoad() {
		BTLE.debugLog(.Medium, "Canceling load on \(self.name), current state: \(self.state.description)")
		if self.loadingState == .Loading {
			BTLE.debugLog(.Medium, "Aborting service load on \(self.name)")
			self.loadingState = .LoadingCancelled
		}
		
		for svc in self.services { svc.cancelLoad() }
	}
	
	public var ignored: Ignored = .Not {
		didSet {
			if oldValue != self.ignored {
				if self.ignored == .BlackList {
					BTLE.scanner.addIgnoredPeripheral(self)
				} else if self.ignored == .Not {
					BTLE.scanner.removeIgnoredPeripheral(self)
				}
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
	
	public func serviceWithUUID(uuid: CBUUID) -> BTLEService? { return self.services.filter({ $0.cbService.UUID == uuid }).last }
	public func characteristicFromCBCharacteristic(characteristic: CBCharacteristic) -> BTLECharacteristic? {
		if let service = self.serviceWithUUID(characteristic.service.UUID) {
			if let chr = service.characteristicWithUUID(characteristic.UUID) {
				return chr
			}
		}
		BTLE.debugLog(.High, "Unabled to find characteristic \(characteristic) \(self.name), current state: \(self.state.description)")
		return nil
	}
	
	public func reloadServices() {
		self.services = []
		if self.ignored == .CheckingForServices {
			self.cbPeripheral.discoverServices(nil)
		} else {
			self.cbPeripheral.discoverServices(nil)
		}
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
		BTLE.debugLog(.Medium, "BTLE Peripheral: Finished loading \(service.uuid), \(self.numberOfLoadingServices) left")
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
		
		let service = BTLEService.createService(service: cbService, onPeriperhal: self)
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
			btle_dispatch_main { [weak self] in
				if let me = self {
					let timeSinceLastComms = abs(me.lastCommunicatedAt.timeIntervalSinceNow)
					if BTLE.manager.deviceLifetime > timeSinceLastComms {
						let timeoutInverval = (BTLE.manager.deviceLifetime - timeSinceLastComms)
						
						// if timeoutInverval < 3 { println("BTLE Peripheral: short term timer: \(timeSinceLastComms) sec") }
						
						me.visibilityTimer?.invalidate()
						me.visibilityTimer = NSTimer.scheduledTimerWithTimeInterval(timeoutInverval, target: me, selector: "disconnectDueToTimeout", userInfo: nil, repeats: false)
					} else if BTLE.manager.deviceLifetime > 0 {
						me.disconnectDueToTimeout()
					}
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
		if self.ignored == .Not { NSNotification.postNotification(name, object: self) }
	}

	//=============================================================================================
	//MARK: Delegate - Peripheral
	
	public func peripheral(peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: NSError?) {
		self.rssi = RSSI.integerValue
	}

	public func peripheralDidUpdateName(peripheral: CBPeripheral) {
		self.name = peripheral.name
		self.sendNotification(BTLE.notifications.peripheralDidUpdateName)
		BTLE.debugLog(.Medium, "Peripheral: Updated name for: \(self.name)") 
	}

	//=============================================================================================
	//MARK: Delegate - Service
	public func peripheral(peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
		for invalidated in invalidatedServices {
			if self.shouldLoadService(invalidated) {
				self.findOrCreateService(invalidated).reload()
			}
		}
	}
	
	public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
		BTLE.debugLog(.Medium, "Discovered \(self.cbPeripheral.services?.count ?? 0) on \(self.name)")
		
		if let services = self.cbPeripheral.services {
			if self.ignored == .CheckingForServices {
				for svc in services {
					if BTLE.manager.services.contains(svc.UUID) {
						self.ignored = .Not
						break
					}
				}
				
				if self.ignored != .Not {
					self.ignored = .MissingServices
					return
				}
			}
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

	public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
		if self.shouldLoadService(service) {
			self.findOrCreateService(service).updateCharacteristics()
		}
	}
	
	public func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
		if self.shouldLoadService(characteristic.service) {
			self.findOrCreateService(characteristic.service).didLoadCharacteristic(characteristic, error: error)
		}
	}
	
	public func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
		self.characteristicFromCBCharacteristic(characteristic)?.didWriteValue(error)
	}
	
	public func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
		self.characteristicFromCBCharacteristic(characteristic)?.didUpdateNotifyValue()
	}
	
	public func peripheral(peripheral: CBPeripheral, didDiscoverDescriptorsForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
		self.characteristicFromCBCharacteristic(characteristic)?.loadDescriptors()
	}
	
	public func peripheral(peripheral: CBPeripheral, didUpdateValueForDescriptor descriptor: CBDescriptor, error: NSError?) {
		self.characteristicFromCBCharacteristic(descriptor.characteristic)?.didUpdateValueForDescriptor(descriptor)
	}
	
	public func peripheral(peripheral: CBPeripheral, didWriteValueForDescriptor descriptor: CBDescriptor, error: NSError?) {
		self.characteristicFromCBCharacteristic(descriptor.characteristic)?.didWriteValueForDescriptor(descriptor)
	}
	
	//=============================================================================================
	//MARK: For overriding

	
	public func shouldLoadService(service: CBService) -> Bool {
		return true
	}
}

