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

protocol BTLEPeripheralProtocol {
	init();
	init(peripheral: CBPeripheral, RSSI: Int?, advertisementData adv: [NSObject: AnyObject]?);
}


let DeviceInfoServiceUUID = CBUUID(string: "0x180A")

let SerialNumberCharacteristicUUID = CBUUID(string: "0x2A25")
let ModelNumberCharacteristicUUID = CBUUID(string: "0x2A24")
let FirmwareVersionCharacteristicUUID = CBUUID(string: "0x2A26")
let HardwareRevisionCharacteristicUUID = CBUUID(string: "0x2A27")
let SoftwareRevisionCharacteristicUUID = CBUUID(string: "0x2A28")
let ManufacturersNameCharacteristicUUID = CBUUID(string: "0x2A29")
let RegulatoryCertificationDataCharacteristicUUID = CBUUID(string: "0x2A2A")
let PnPIDCharacteristicUUID = CBUUID(string: "0x2A50")


public class BTLEPeripheral: NSObject, CBPeripheralDelegate, Printable {
	public enum State { case Discovered, Connecting, Connected, Disconnecting, Undiscovered, Unknown }
	
	public var cbPeripheral: CBPeripheral!
	public var uuid: NSUUID!
	public var name: String!
	public var lastCommunicatedAt: NSDate! { didSet {
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
				if BTLE.debugging { println("Loaded device: \(self.fullDescription)") }
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
			self.loadServices()
			
			
		case .Disconnecting: fallthrough
		case .Discovered:
			if self.loadingState == .Loading { self.loadingState = .LoadingCancelled }
			
		case .Undiscovered:
			self.disconnect()
			
		default: break
		}
	}}
	public var rssi: Int? { didSet {
		self.lastCommunicatedAt = NSDate()
		self.sendNotification(BTLE.notifications.peripheralDidUpdateRSSI)
	}}
	
	
	func modulateRSSI(newRSSI: Int) {
		if abs(newRSSI) == 127 { return }
		if let rssi = self.rssi {
			var delta = abs(Float(newRSSI - rssi))
			if delta < 5 {
				self.lastCommunicatedAt = NSDate()
				self.sendNotification(BTLE.notifications.peripheralDidUpdateRSSI)
				return
			}
			
			self.rssi = rssi + Int(ceilf(Float(newRSSI - rssi) * 0.25))
		} else if newRSSI < 127 {
			self.rssi = newRSSI
		}
	}
	
	public override required init() {
		super.init()
	}
	
	public required init(peripheral: CBPeripheral, RSSI: Int?, advertisementData adv: [NSObject: AnyObject]?) {
		cbPeripheral = peripheral
		uuid = peripheral.identifier
		name = peripheral.name ?? "unknown"
		lastCommunicatedAt = NSDate()
		if let adv = adv { advertisementData = adv }
		
		ignored = BTLE.manager.scanner.ignoredPeripheralUUIDs.contains(peripheral.identifier.UUIDString)
		if ignored && BTLE.debugging { println("Ignoring peripheral: \(name), \(uuid)") }
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
		
		BTLE.manager.scanner.cbCentral.cancelPeripheralConnection(self.cbPeripheral)
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
		}
		
		return string
	}

	public var fullDescription: String {
		var desc = "\(self.summaryDescription)\n\(self.advertisementData)"
		
		for svc in self.services {
			desc = desc + "\n" + svc.description
		}
		
		return desc
	}
	
	public func updateRSSI() {
		self.cbPeripheral.readRSSI()
	}
	
	public func serviceWithUUID(uuid: CBUUID) -> BTLEService? { return filter(self.services, { $0.cbService.UUID == uuid }).last }

	
	//=============================================================================================
	//MARK: Internal
	var forceReload = false
	func loadServices(reload: Bool = false) {
		self.sendNotification(BTLE.notifications.peripheralDidBeginLoading)
		self.loadingState = .Loading
		self.forceReload = reload
		self.cbPeripheral.discoverServices(nil)
	}
	
	func didFinishLoadingService(service: BTLEService) {
		if self.numberOfPendingServices == 0 {
			self.loadingState = .Loaded
		}
	}
	
	
	var numberOfPendingServices: Int {
		var count = 0
		
		for chr in self.services {
			if chr.loading { count++ }
		}
		return count
	}

	func addService(cbService: CBService) -> BTLEService {
		if let service = self.serviceWithUUID(cbService.UUID) {
			if self.forceReload { service.load() }
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
					
					if timeoutInverval < 3 {
						println("short term timer: \(timeSinceLastComms) sec")
					}
					
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
	//MARK: Delegate

	public func peripheral(peripheral: CBPeripheral!, didModifyServices invalidatedServices: [AnyObject]!) {
		var remainingServices = self.services
		
		for invalidated in invalidatedServices as! [CBService] {
			self.addService(invalidated).load()
		}
	}
	
	public func peripheral(peripheral: CBPeripheral!, didDiscoverServices error: NSError!) {
		if let services = self.cbPeripheral.services as? [CBService] {
			for svc in services {
				self.addService(svc)
			}
			
			if self.numberOfPendingServices == 0 {
				self.loadingState = .Loaded
			}
		}
	}

	
	public func peripheralDidUpdateName(peripheral: CBPeripheral!) {
		self.name = peripheral.name
		self.sendNotification(BTLE.notifications.peripheralDidUpdateName)
		if BTLE.debugging { println("Updated name for: \(self.name)") }
	}

	public func peripheral(peripheral: CBPeripheral!, didDiscoverCharacteristicsForService service: CBService!, error: NSError!) {
		self.addService(service).updateCharacteristics()
	}
	
	
	public func peripheral(peripheral: CBPeripheral!, didUpdateValueForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
		self.addService(characteristic.service).didLoadCharacteristic(characteristic)
	}

	public func peripheral(peripheral: CBPeripheral!, didReadRSSI RSSI: NSNumber!, error: NSError!) {
		if let rssi = RSSI {
			self.rssi = rssi.integerValue
		}

		//println("updated RSSI for \(self)")
	}

}

