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
	public var dispatchQueue = dispatch_queue_create("BTLE.CentralManager queue", DISPATCH_QUEUE_SERIAL)
	public var cbCentral: CBCentralManager!

	public var peripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var ignoredPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var oldPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	

	//=============================================================================================
	//MARK: Actions

	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return (NSBundle.mainBundle().infoDictionary?["CFBundleIdentifier"] as? String ?? "btle") + "-scanner" }

	
	//=============================================================================================
	//MARK: State changers
	weak var searchTimer: NSTimer?
	
	var coreBluetoothFilteredServices: [CBUUID] { return BTLE.manager.serviceFilter == .CoreBluetooth ? BTLE.manager.services : [] }
	
	func startScanning(duration: NSTimeInterval = 0.0) {
		self.setupCBCentral()
		
		self.oldPeripherals = self.oldPeripherals.union(self.peripherals.union(self.ignoredPeripherals))
		self.ignoredPeripherals = Set<BTLEPeripheral>()
		self.peripherals = Set<BTLEPeripheral>()
		
		if self.cbCentral.state == .PoweredOn {
			BTLE.manager.scanningState = .Active
			NSNotification.postNotification(BTLE.notifications.willStartScan, object: self)
			var options = BTLE.manager.monitorRSSI ? [CBCentralManagerScanOptionAllowDuplicatesKey: true] : [:]
			if BTLE.debugLevel > .None { println(BTLE.manager.services.count > 0 ? "BTLE: Starting scan for \(BTLE.manager.services)" : "BTLE: Starting unfiltered scan") }
			self.cbCentral.scanForPeripheralsWithServices(self.coreBluetoothFilteredServices, options: options)
			if duration != 0.0 {
				self.searchTimer = NSTimer.scheduledTimerWithTimeInterval(duration, target: self, selector: "stopScanning", userInfo: nil, repeats: false)
			}
		} else {
			BTLE.manager.scanningState = .StartingUp
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
				if let info = advertisementData where per.ignored == .MissingServices {
					per.updateIgnoredWithAdvertisingData(info)
					
					if per.ignored == .Not {
						self.peripherals.insert(per)
						self.ignoredPeripherals.remove(per)
						per.sendNotification(BTLE.notifications.peripheralWasDiscovered)
						return per
					}
				}
				return per
			}
		}

		for per in self.oldPeripherals {
			if per.uuid == peripheral.identifier {
				self.oldPeripherals.remove(per)
				if per.ignored != .Not {
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
		if per.ignored != .Not {
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
			} else if BTLE.manager.scanningState == .StartingUp {
				self.startScanning()
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
		if per.state != .Connected {
			per.state = .Connected
			per.sendNotification(BTLE.notifications.peripheralDidConnect)
		}
	}
	
	public func centralManager(centralManager: CBCentralManager!, didDisconnectPeripheral peripheral: CBPeripheral!, error: NSError!) {
		var per = self.addPeripheral(peripheral)
		if per.state != .Discovered {
			per.state = .Discovered
			per.sendNotification(BTLE.notifications.peripheralDidDisconnect)
		}
	}
	
	//=============================================================================================
	//MARK: Utility
	
	func fetchConnectedPeripherals() {
		var connected = self.cbCentral?.retrieveConnectedPeripheralsWithServices(self.coreBluetoothFilteredServices) as! [CBPeripheral]
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
		
		if BTLE.debugLevel > .None && list.count > 0 { println("BTLE: Ignored IDs: " + NSArray(array: list).componentsJoinedByString(", ")) }
		
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