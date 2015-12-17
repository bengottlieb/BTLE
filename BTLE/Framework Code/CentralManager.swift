//
//  BTLECentralManager.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth
import Gulliver

public class BTLECentralManager: NSObject, CBCentralManagerDelegate {
	public var dispatchQueue = dispatch_queue_create("BTLE.CentralManager queue", DISPATCH_QUEUE_SERIAL)
	public var cbCentral: CBCentralManager!

	public var peripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var ignoredPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var oldPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	var pendingPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	
	public var state: BTLE.State { get { return self.internalState }}
	var internalState: BTLE.State = .Off { didSet {
		if oldValue == self.internalState { return }
		BTLE.debugLog(.Medium, "Changing state to \(self.internalState) from \(oldValue), Central state: \(self.cbCentral?.state.rawValue)")
		self.stateChangeCounter++
		switch self.internalState {
		case .Off:
			NSNotification.postNotificationOnMainThread(BTLE.notifications.didFinishScan, object: self)
			break
			
		case .StartingUp:
			if oldValue != .Active {
				NSNotification.postNotificationOnMainThread(BTLE.notifications.willStartScan, object: self)
			}
			if let central = self.cbCentral where central.state == .PoweredOn { self.internalState = .Active }
			break
			
		case .Active:
			self.startCentralScanning()
			NSNotification.postNotificationOnMainThread(BTLE.notifications.didStartScan, object: self)
			
		case .Idle:
			NSNotification.postNotificationOnMainThread(BTLE.notifications.didFinishScan, object: self)
			self.stopScanning()
			
		case .ShuttingDown: break
		case .Cycling:
			switch oldValue {
			case .Off: btle_delay(0.01) { self.restartScanning() }
			case .ShuttingDown: break
			default: btle_delay(0.01) { self.turnOff() }
			}
			
		case .PowerInterupted: break
		}
		self.stateChangeCounter--
		}}
	

	//=============================================================================================
	//MARK: Actions

	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return (NSBundle.mainBundle().infoDictionary?["CFBundleIdentifier"] as? String ?? "btle") + "-scanner" }

	
	//=============================================================================================
	//MARK: State changers
	weak var searchTimer: NSTimer?
	
	var coreBluetoothFilteredServices: [CBUUID] { return BTLE.manager.serviceFilter == .CoreBluetooth ? BTLE.manager.services : [] }
	
	func restartScanning() {
		self.internalState = .Idle
		self.startScanning()
	}
	
	public func startScanning(duration: NSTimeInterval? = nil) {
		dispatch_async(self.dispatchQueue) {
			if self.state == .Active || self.state == .StartingUp { return }			//already scanning
			if self.state == .ShuttingDown { self.internalState = .Cycling }
			if self.state == .Cycling { return }
			
			self.setupCBCentral()
			
			self.oldPeripherals = self.oldPeripherals.union(self.peripherals.union(self.ignoredPeripherals))
			self.ignoredPeripherals = Set<BTLEPeripheral>()
			self.peripherals = Set<BTLEPeripheral>()
			
			if let duration = duration { self.pendingDuration = duration }
			if self.cbCentral.state == .PoweredOn {
				self.startCentralScanning()
			} else {
				self.internalState = .StartingUp
			}
		}
	}
	
	var pendingDuration: NSTimeInterval = 0.0
	func startCentralScanning() {
		dispatch_async(self.dispatchQueue) {
			self.internalState = .Active
			let options = BTLE.manager.monitorRSSI ? [CBCentralManagerScanOptionAllowDuplicatesKey: true] : [:]
			BTLE.debugLog(.Medium, BTLE.manager.services.count > 0 ? "Starting scan for \(BTLE.manager.services)" : "Starting unfiltered scan")
			self.cbCentral.scanForPeripheralsWithServices(self.coreBluetoothFilteredServices.count > 0 ? self.coreBluetoothFilteredServices : nil, options: options)
			if self.pendingDuration != 0.0 {
				self.searchTimer = NSTimer.scheduledTimerWithTimeInterval(self.pendingDuration, target: self, selector: "stopScanning", userInfo: nil, repeats: false)
			}
		}
	}
	
	public func stopScanning() {
		dispatch_async(self.dispatchQueue) {
			self.searchTimer?.invalidate()
			if let centralManager = self.cbCentral where self.internalState == .Active {
				if self.internalState != .Cycling && self.internalState != .Idle { self.internalState = .ShuttingDown }
				centralManager.stopScan()
				if self.stateChangeCounter == 0 {
					let oldState = self.internalState
					self.internalState = .Idle

					if oldState == .Cycling { self.restartScanning() }
				}
			}
		}
	}
	
	public func turnOff() {
		if self.cbCentral != nil && self.state != .ShuttingDown && self.state != .Off {
			BTLE.debugLog(.Medium, "Turning Off")
			self.stopScanning()

			self.cbCentral = nil
			if self.stateChangeCounter == 0 {
				let oldState = self.internalState
				self.internalState = .Off
				
				if oldState == .Cycling { self.restartScanning() }
			}
		}
	}

	//=============================================================================================
	//MARK: setup
	var stateChangeCounter = 0 { didSet { assert(stateChangeCounter >= 0, "Illegal value for stateChangeCounter") }}
	func setupCBCentral(rebuild: Bool = false) {
		if self.cbCentral == nil || rebuild {
			self.turnOff()
			
			var options: [String: AnyObject] = [CBCentralManagerOptionShowPowerAlertKey: true]
			
			if BTLE.browseInBackground { options[CBCentralManagerOptionRestoreIdentifierKey] = BTLECentralManager.restoreIdentifier }
			
			self.cbCentral = CBCentralManager(delegate: self, queue: self.dispatchQueue, options: options)
			if self.cbCentral.state == .PoweredOn { self.fetchConnectedPeripherals() }
		}
	}
	
	func existingPeripheral(peripheral: CBPeripheral) -> BTLEPeripheral? {
		for perGroup in [self.peripherals, self.ignoredPeripherals, self.pendingPeripherals] {
			for per in perGroup {
				if per.uuid == peripheral.identifier {
					return per
				}
			}
		}

		return nil
	}
	
	func addPeripheral(peripheral: CBPeripheral, RSSI: Int? = nil, advertisementData: [NSObject: AnyObject]? = nil) -> BTLEPeripheral? {
		print("Discovered: \(advertisementData)")
		if let existing = self.existingPeripheral(peripheral) {
			if let rssi = RSSI { existing.setCurrentRSSI(rssi) }
			if let advertisementData = advertisementData { existing.advertisementData = advertisementData }
			return existing
		}
		
		for ignoredPer in self.ignoredPeripherals {
			if ignoredPer.uuid == peripheral.identifier {
				if let info = advertisementData where ignoredPer.ignored == .MissingServices {
					ignoredPer.updateIgnoredWithAdvertisingData(info)
					
					if ignoredPer.ignored == .Not {
						self.peripherals.insert(ignoredPer)
						self.ignoredPeripherals.remove(ignoredPer)
						ignoredPer.sendNotification(BTLE.notifications.peripheralWasDiscovered)
						return ignoredPer
					}
				}
				return ignoredPer
			}
		}

		for oldPer in self.oldPeripherals {
			if oldPer.uuid == peripheral.identifier {
				self.oldPeripherals.remove(oldPer)
				if oldPer.ignored != .Not {
					self.ignoredPeripherals.insert(oldPer)
				} else {
					self.peripherals.insert(oldPer)
					if let rssi = RSSI { oldPer.setCurrentRSSI(rssi) }
					if let advertisementData = advertisementData { oldPer.advertisementData = advertisementData }
					return oldPer
				}
			}
		}
		
		let per: BTLEPeripheral
		
		if let perClass = BTLE.registeredClasses.peripheralClass {
			per = perClass.init(peripheral: peripheral, RSSI: RSSI, advertisementData: advertisementData)
		} else {
			if BTLE.manager.ignoreBeaconLikeDevices, let _ = advertisementData?[CBAdvertisementDataManufacturerDataKey] as? NSData {
//				print("\(advertisementData)")
//				if let beacon = BTLEBeacon.beaconWithData(mfrData) {
//					print("Found beacon: \(beacon)")
//				}
				return nil
			}
			
			per = BTLEPeripheral(peripheral: peripheral, RSSI: RSSI, advertisementData: advertisementData)
		}
		if per.ignored != .Not {
			if per.ignored != .CheckingForServices {
				self.ignoredPeripherals.insert(per)
			} else {
				self.pendingPeripherals.insert(per)
			}
			return per
		} else {
			self.peripherals.insert(per)
		}
		
		per.sendNotification(BTLE.notifications.peripheralWasDiscovered)
		return per
	}

	func pendingPeripheralFinishLoadingServices(peripheral: BTLEPeripheral) {
		dispatch_async(self.dispatchQueue) {
			if peripheral.ignored == .MissingServices {
				self.ignoredPeripherals.insert(peripheral)
				peripheral.sendNotification(BTLE.notifications.peripheralWasDiscovered)
				self.pendingPeripherals.remove(peripheral)
			} else if peripheral.ignored == .Not {
				self.peripherals.insert(peripheral)
				peripheral.sendNotification(BTLE.notifications.peripheralWasDiscovered)
				self.pendingPeripherals.remove(peripheral)
			}
		}
	}
	
	//=============================================================================================
	//MARK: CBCentralManagerDelegate
	public func centralManagerDidUpdateState(centralManager: CBCentralManager) {
		dispatch_async(self.dispatchQueue) {
			BTLE.debugLog(.Medium, "Central manager updated state to \(centralManager.state.rawValue), my state: \(self.internalState)")
			switch centralManager.state {
			case .PoweredOn:
				if self.internalState == .PowerInterupted {
					self.internalState = .Active
				} else if self.internalState == .StartingUp {
					self.internalState = .Active
				}
				self.fetchConnectedPeripherals()

			case .PoweredOff:
				if self.internalState == .Active || self.internalState == .StartingUp {
					self.internalState = .PowerInterupted
					self.stopScanning()
				} else {
					self.internalState = .Off
				}
			default: break
			}
		}

	}
	
	public func centralManager(centralManager: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
		dispatch_async(self.dispatchQueue) {
			self.addPeripheral(peripheral, RSSI: RSSI.integerValue as BTLEPeripheral.RSSValue, advertisementData: advertisementData)
		}
	}
	
	public func centralManager(centralManager: CBCentralManager, willRestoreState dict: [String : AnyObject]) {
		dispatch_async(self.dispatchQueue) {
			self.cbCentral = centralManager
			centralManager.delegate = self
			if self.cbCentral.state == .PoweredOn { self.fetchConnectedPeripherals() }
		}
	}

	public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
		dispatch_async(self.dispatchQueue) {
			if BTLE.debugLevel > .None {
				BTLE.debugLog(.Medium, "Failed to connect to peripheral: \(peripheral): \(error)")
			}
			if let existing = self.existingPeripheral(peripheral) {
				existing.didFailToConnect(error)
			}
		}
	}
	
	public func centralManager(centralManager: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
		dispatch_async(self.dispatchQueue) {
			if let per = self.addPeripheral(peripheral) where per.state != .Connected {
				per.state = .Connected
				per.sendNotification(BTLE.notifications.peripheralDidConnect)
			}
		}
	}
	
	public func centralManager(centralManager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
		dispatch_async(self.dispatchQueue) {
			if let per = self.addPeripheral(peripheral) where per.state != .Discovered {
				per.state = .Discovered
				per.sendNotification(BTLE.notifications.peripheralDidDisconnect)
			}
		}
	}
	
	//=============================================================================================
	//MARK: Utility
	
	func fetchConnectedPeripherals() {
		dispatch_async(self.dispatchQueue) {
			if let connected = self.cbCentral?.retrieveConnectedPeripheralsWithServices(self.coreBluetoothFilteredServices) {
				for peripheral in connected {
					self.addPeripheral(peripheral)
				}
				self.internalState = .Active
			}
		}
	}

	//=============================================================================================
	//MARK: Ignored Devices
	let ignoredPeripheralUUIDsKey = DefaultsKey<[String]>("ignored-btle-uuids")
	lazy var ignoredPeripheralUUIDs: Set<String> = {
		let list = NSUserDefaults.get(self.ignoredPeripheralUUIDsKey)
		
		if list.count > 0 { BTLE.debugLog(.Low, "Ignored IDs: " + NSArray(array: list).componentsJoinedByString(", ")) }
		
		return Set(list)
	}()
	func addIgnoredPeripheral(peripheral: BTLEPeripheral) {
		self.peripherals.remove(peripheral)
		self.ignoredPeripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.insert(peripheral.uuid.UUIDString)
		NSUserDefaults.set(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func removeIgnoredPeripheral(peripheral: BTLEPeripheral) {
		self.ignoredPeripherals.remove(peripheral)
		self.peripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.remove(peripheral.uuid.UUIDString)
		NSUserDefaults.set(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func isPeripheralIgnored(peripheral: BTLEPeripheral) -> Bool {
		return self.ignoredPeripherals.contains(peripheral) || self.ignoredPeripheralUUIDs.contains(peripheral.uuid.UUIDString)
	}

}