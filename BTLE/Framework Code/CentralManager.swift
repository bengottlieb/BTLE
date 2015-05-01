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

	public var peripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var ignoredPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var oldPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	

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
		
		self.oldPeripherals = self.oldPeripherals.union(self.peripherals.union(self.ignoredPeripherals))
		self.ignoredPeripherals = Set<BTLEPeripheral>()
		self.peripherals = Set<BTLEPeripheral>()
		
		if self.cbCentral.state == .PoweredOn {
			NSNotification.postNotification(BTLE.notifications.willStartScan, object: self)
			var options = BTLE.manager.monitorRSSI ? [CBCentralManagerScanOptionAllowDuplicatesKey: true] : [:]
			if BTLE.debugLevel > .None { println(BTLE.manager.services.count > 0 ? "Starting scan for \(BTLE.manager.services)" : "Starting unfiltered scan") }
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
			if self.stateChangeCounter == 0 { BTLE.manager.scanningState = .Idle }
		}
	}
	
	func turnOff() {
		self.stopScanning()

		if let centralManager = self.cbCentral {
			self.cbCentral = nil
			if self.stateChangeCounter == 0 { BTLE.manager.scanningState = .Off }
		}
	}
	
	weak var updateScanTimer: NSTimer?
	func updateScan() {
		dispatch_async_main {
			if BTLE.manager.scanningState == .Active {
				self.updateScanTimer?.invalidate()
				self.updateScanTimer = NSTimer.scheduledTimerWithTimeInterval(0.0001, target: self, selector: "cycleScanning", userInfo: nil, repeats: false)
			}
		}
	}
	
	//=============================================================================================
	//MARK: Timers
	func cycleScanning() {
		self.stateChangeCounter++
		self.stopScanning()
		self.startScanning()
		self.stateChangeCounter--
	}
	
	
	//=============================================================================================
	//MARK: setup
	var stateChangeCounter = 0 { didSet { assert(stateChangeCounter >= 0, "Illegal value for stateChangeCounter") }}
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
				if let rssi = RSSI { per.setCurrentRSSI(rssi) }
				if let advertisementData = advertisementData { per.advertisementData = advertisementData }
				return per
			}
		}

		for per in self.ignoredPeripherals {
			if per.uuid == peripheral.identifier {
				return per
			}
		}

		for per in self.oldPeripherals {
			if per.uuid == peripheral.identifier {
				self.oldPeripherals.remove(per)
				if per.ignored {
					self.ignoredPeripherals.insert(per)
				} else {
					self.peripherals.insert(per)
					if let rssi = RSSI { per.setCurrentRSSI(rssi) }
					if let advertisementData = advertisementData { per.advertisementData = advertisementData }
					return per
				}
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
			self.peripherals.insert(per)
		}
		
		per.sendNotification(BTLE.notifications.peripheralWasDiscovered)
		return per
	}

	//=============================================================================================
	//MARK: CBCentralManagerDelegate
	public func centralManagerDidUpdateState(centralManager: CBCentralManager!) {
		switch centralManager.state {
		case .PoweredOn:
			if BTLE.manager.scanningState == .PowerInterupted {
				BTLE.manager.scanningState = .Active
			}
			self.fetchConnectedPeripherals()

		case .PoweredOff:
			if BTLE.manager.scanningState == .Active || BTLE.manager.scanningState == .StartingUp {
				BTLE.manager.scanningState = .PowerInterupted
				self.stopScanning()
			}
		default: break
		}

	}
	
	public func centralManager(centralManager: CBCentralManager!, didDiscoverPeripheral peripheral: CBPeripheral!, advertisementData: [NSObject : AnyObject]!, RSSI: NSNumber!) {
		var per = self.addPeripheral(peripheral, RSSI: RSSI.integerValue as BTLEPeripheral.RSSValue, advertisementData: advertisementData)
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
	lazy var ignoredPeripheralUUIDs: Set<String> = {
		let list = NSUserDefaults.keyedObject(self.ignoredPeripheralUUIDsKey) as? [String] ?? []
		
		if BTLE.debugLevel > .None && list.count > 0 { println("Ignored IDs: " + NSArray(array: list).componentsJoinedByString(", ")) }
		
		return Set(list)
	}()
	func addIgnoredPeripheral(peripheral: BTLEPeripheral) {
		self.peripherals.remove(peripheral)
		self.ignoredPeripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.insert(peripheral.uuid.UUIDString)
		NSUserDefaults.setKeyedObject(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func removeIgnoredPeripheral(peripheral: BTLEPeripheral) {
		self.ignoredPeripherals.remove(peripheral)
		self.peripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.remove(peripheral.uuid.UUIDString)
		NSUserDefaults.setKeyedObject(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func isPeripheralIgnored(peripheral: BTLEPeripheral) -> Bool {
		return self.ignoredPeripherals.contains(peripheral) || self.ignoredPeripheralUUIDs.contains(peripheral.uuid.UUIDString)
	}

}