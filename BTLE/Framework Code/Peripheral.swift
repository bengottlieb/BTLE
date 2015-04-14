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
	public var lastCommunicatedAt: NSDate! { didSet { self.updateVisibilityTimer() }}
	public var loadingState = BTLE.LoadingState.NotLoaded {
		didSet {
			if self.loadingState == .Loaded { NSNotification.postNotification(BTLE.notifications.peripheralDidFinishLoading, object: self) }
		}
	}
	public var services: [BTLEService] = []
	public var advertisementData: [NSObject: AnyObject] = [:]
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
		if self.state == .Undiscovered {
			self.state = .Discovered
			NSNotification.postNotification(BTLE.notifications.peripheralDidRegainComms, object: self)
		}
		self.lastCommunicatedAt = NSDate()
		NSNotification.postNotification(BTLE.notifications.peripheralDidUpdateRSSI, object: self)
	}}
	
	public override required init() {
		super.init()
	}
	
	public required init(peripheral: CBPeripheral, RSSI: Int?, advertisementData adv: [NSObject: AnyObject]?) {
		cbPeripheral = peripheral
		uuid = peripheral.identifier
		name = peripheral.name ?? "unknown"
		lastCommunicatedAt = NSDate()
		if let adv = adv { advertisementData = adv }
		
		super.init()
		peripheral.delegate = self
		peripheral.readRSSI()
		self.rssi = RSSI
		self.updateVisibilityTimer()
	}
	
	public func connect() {
		self.state = .Connecting
		BTLE.manager.central.cbCentral.connectPeripheral(self.cbPeripheral, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
	}
	
	public func disconnect() {
		if self.state == .Connected { self.state = .Disconnecting }
		
		BTLE.manager.central.cbCentral.cancelPeripheralConnection(self.cbPeripheral)
	}
	
	public override var description: String {
		var string = "(\(self.rssi ?? -127)) BT \(self.name) \(self.uuid.UUIDString)"
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

	public func updateRSSI() {
		self.cbPeripheral.readRSSI()
	}
	
	public func serviceWithUUID(uuid: CBUUID) -> BTLEService? { return filter(self.services, { $0.cbService.UUID == uuid }).last }

	
	//=============================================================================================
	//MARK: Internal
	var forceReload = false
	func loadServices(reload: Bool = false) {
		NSNotification.postNotification(BTLE.notifications.peripheralDidBeginLoading, object: self)
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
			NSNotification.postNotification(BTLE.notifications.peripheralDidLoseComms, object: self)
		}
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
		for svc in self.cbPeripheral.services as! [CBService] {
			self.addService(svc)
		}
		
		if self.numberOfPendingServices == 0 {
			self.loadingState = .Loaded
		}
	}

	
	public func peripheralDidUpdateName(peripheral: CBPeripheral!) {
		self.name = peripheral.name
		NSNotification.postNotification(BTLE.notifications.peripheralDidUpdateName, object: self)
	//	println("Updated name: \(self.name)")
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

