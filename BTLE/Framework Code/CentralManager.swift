//
//  BTLECentralManager.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth
import SA_Swift

public class BTLECentralManager: NSObject, CBCentralManagerDelegate {
	var dispatchQueue = dispatch_queue_create("BTLE.CentralManager queue", DISPATCH_QUEUE_SERIAL)
	var cbCentral: CBCentralManager!

	public var peripherals: [BTLEPeripheral] = []
	public var ignoredPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	

	//=============================================================================================
	//MARK: Actions

	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return NSBundle.mainBundle().infoDictionary?["CFBundleIdentifier"] as? String ?? "ident" }

	
	//=============================================================================================
	//MARK: State changers
	weak var searchTimer: NSTimer?
	
	func startScanning(duration: NSTimeInterval = 0.0) {
		self.setupCBCentral()
		
		if self.cbCentral.state == .PoweredOn {
			NSNotification.postNotification(BTLE.notifications.willStartScan, object: self)
			var options = BTLE.manager.monitorRSSI ? [CBCentralManagerScanOptionAllowDuplicatesKey: true] : [:]
			self.cbCentral.scanForPeripheralsWithServices(BTLE.manager.services, options: options)
			if duration != 0.0 {
				self.searchTimer = NSTimer.scheduledTimerWithTimeInterval(duration, target: self, selector: "stopScanning", userInfo: nil, repeats: false)
			}
		}
	}
	
	func stopScanning() {
		self.searchTimer?.invalidate()
		if let centralManager = self.cbCentral {
			centralManager.stopScan()
			NSNotification.postNotification(BTLE.notifications.didFinishScan, object: self)
			if !self.changingState { BTLE.manager.scanningState = .Off }
		}
	}
	
	func turnOff() {
		self.stopScanning()

		if let centralManager = self.cbCentral {
			self.cbCentral = nil
			if !self.changingState { BTLE.manager.scanningState = .Off }
		}
	}
	
	weak var updateScanTimer: NSTimer?
	func updateScan() {
		dispatch_async_main {
			self.updateScanTimer?.invalidate()
			self.updateScanTimer = NSTimer.scheduledTimerWithTimeInterval(0.0001, target: self, selector: "updateScanTimerFired", userInfo: nil, repeats: false)
		}
	}
	
	//=============================================================================================
	//MARK: Timers
	func updateScanTimerFired() {
		self.stopScanning()
		self.startScanning()
	}
	
	
	//=============================================================================================
	//MARK: setup
	var changingState = false
	func setupCBCentral(rebuild: Bool = false) {
		if self.cbCentral == nil || rebuild {
			self.turnOff()
			
			var options: [NSObject: AnyObject] = [CBCentralManagerOptionShowPowerAlertKey: true, CBCentralManagerOptionRestoreIdentifierKey: BTLECentralManager.restoreIdentifier]
			
			self.cbCentral = CBCentralManager(delegate: self, queue: self.dispatchQueue, options: options)
			if self.cbCentral.state == .PoweredOn { self.fetchConnectedPeripherals() }
		}
	}
	
	func addPeripheral(peripheral: CBPeripheral, RSSI: Int? = nil, advertisementData: [NSObject: AnyObject]? = nil) -> BTLEPeripheral {
		for per in self.peripherals {
			if per.uuid == peripheral.identifier {
				if let rssi = RSSI { per.rssi = rssi }
				if let advertisementData = advertisementData { per.advertisementData = advertisementData }
				return per
			}
		}

		for per in self.ignoredPeripherals {
			if per.uuid == peripheral.identifier {
				return per
			}
		}

		let per: BTLEPeripheral
		
		if let perClass = BTLE.registeredClasses.peripheralClass {
			per = perClass(peripheral: peripheral, RSSI: RSSI, advertisementData: advertisementData)
		} else {
			per = BTLEPeripheral(peripheral: peripheral, RSSI: RSSI, advertisementData: advertisementData)
		}
		if per.ignored {
			self.ignoredPeripherals.insert(per)
		} else {
			self.peripherals.append(per)
		}
		
		per.sendNotification(BTLE.notifications.peripheralWasDiscovered)
		return per
	}

	//=============================================================================================
	//MARK: CBCentralManagerDelegate
	public func centralManagerDidUpdateState(centralManager: CBCentralManager!) {
		switch centralManager.state {
		case .PoweredOn: self.fetchConnectedPeripherals()
		default: break
		}

	}
	
	public func centralManager(centralManager: CBCentralManager!, didDiscoverPeripheral peripheral: CBPeripheral!, advertisementData: [NSObject : AnyObject]!, RSSI: NSNumber!) {
		var per = self.addPeripheral(peripheral, RSSI: RSSI.integerValue, advertisementData: advertisementData)
	}
	
	public func centralManager(centralManager: CBCentralManager!, willRestoreState dict: [NSObject : AnyObject]!) {
		self.cbCentral = centralManager
		centralManager.delegate = self
		if self.cbCentral.state == .PoweredOn { self.fetchConnectedPeripherals() }
	}
	
	public func centralManager(centralManager: CBCentralManager!, didConnectPeripheral peripheral: CBPeripheral!) {
		var per = self.addPeripheral(peripheral)
		per.state = .Connected
		per.sendNotification(BTLE.notifications.peripheralDidConnect)
	}
	
	public func centralManager(centralManager: CBCentralManager!, didDisconnectPeripheral peripheral: CBPeripheral!, error: NSError!) {
		var per = self.addPeripheral(peripheral)
		per.state = .Discovered
		per.sendNotification(BTLE.notifications.peripheralDidDisconnect)
	}
	
	//=============================================================================================
	//MARK: Utility
	
	func fetchConnectedPeripherals() {
		var connected = self.cbCentral.retrieveConnectedPeripheralsWithServices(BTLE.manager.services) as! [CBPeripheral]
		for peripheral in connected {
			self.addPeripheral(peripheral)
		}
		BTLE.manager.scanningState = .Active
	}

	//=============================================================================================
	//MARK: Ignored Devices
	let ignoredPeripheralUUIDsKey = "ignored-btle-uuids"
	lazy var ignoredPeripheralUUIDs: Set<String> = { Set(NSUserDefaults.keyedObject(self.ignoredPeripheralUUIDsKey) as? [String] ?? []) }()
	func addIgnoredPeripheral(peripheral: BTLEPeripheral) {
		self.peripherals.remove(peripheral)
		self.ignoredPeripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs = self.ignoredPeripherals.map({ return $0.uuid.UUIDString })
		NSUserDefaults.setKeyedObject(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func removeIgnoredPeripheral(peripheral: BTLEPeripheral) {
		self.ignoredPeripherals.remove(peripheral)
		self.peripherals.append(peripheral)
		
		self.ignoredPeripheralUUIDs = self.ignoredPeripherals.map({ return $0.uuid.UUIDString })
		NSUserDefaults.setKeyedObject(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func isPeripheralIgnored(peripheral: BTLEPeripheral) -> Bool {
		return self.ignoredPeripherals.contains(peripheral) || self.ignoredPeripheralUUIDs.contains(peripheral.uuid.UUIDString)
	}

}