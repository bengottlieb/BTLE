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
import GulliverUI

public class BTLECentralManager: NSObject, CBCentralManagerDelegate {
	public var dispatchQueue = DispatchQueue(label: "BTLE.CentralManager queue")
	public var cbCentral: CBCentralManager!

	public var peripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var ignoredPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	public var oldPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	var pendingPeripherals: Set<BTLEPeripheral> = Set<BTLEPeripheral>()
	
	public var state: BTLE.State { get { return self.internalState }}
	var internalState: BTLE.State = .off { didSet {
		if oldValue == self.internalState { return }
		BTLE.debugLog(.medium, "Changing state to \(self.internalState) from \(oldValue), Central state: \(self.cbCentral?.state.rawValue ?? -1)")
		self.stateChangeCounter += 1
		switch self.internalState {
		case .off:
			Notification.postOnMainThread(name: BTLE.notifications.didFinishScan, object: self)
			break
			
		case .startingUp:
			if oldValue != .active {
				Notification.postOnMainThread(name: BTLE.notifications.willStartScan, object: self)
			}
			if let central = self.cbCentral, central.state == .poweredOn { self.internalState = .active }
			break
			
		case .active:
			self.startCentralScanning()
			Notification.postOnMainThread(name: BTLE.notifications.didStartScan, object: self)
			
		case .idle:
			Notification.postOnMainThread(name: BTLE.notifications.didFinishScan, object: self)
			self.stopScanning()
			
		case .shuttingDown: break
		case .cycling:
			switch oldValue {
			case .off: btle_delay(0.01) { self.restartScanning() }
			case .shuttingDown: break
			default: btle_delay(0.01) { self.turnOff() }
			}
			
		case .powerInterupted: break
		}
		self.stateChangeCounter -= 1
		}}
	

	//=============================================================================================
	//MARK: Actions
	public enum ClearWhichCacheItems { case old, allIncludingConnected }
	public func clearCached(_ which: ClearWhichCacheItems) {
		var count = self.oldPeripherals.count
		self.oldPeripherals = []
		
		count += self.ignoredPeripherals.count
		self.ignoredPeripherals = []
		
		if which == .allIncludingConnected {
			count += self.pendingPeripherals.count
			self.pendingPeripherals = []
			
			count += self.peripherals.count
			self.peripherals = []
		}
		BTLE.debugLog(.medium, "Cleared out \(count) devices")
	}
	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return (Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String ?? "btle") + "-scanner" }

	
	//=============================================================================================
	//MARK: State changers
	weak var searchTimer: Timer?
	
	var coreBluetoothFilteredServices: [CBUUID] { return BTLE.manager.serviceFilter == .coreBluetooth ? BTLE.manager.serviceIDsToScanFor : [] }
	
	func restartScanning() {
		self.internalState = .idle
		self.startScanning()
	}
	
	public func startScanning(for duration: TimeInterval? = nil) {
		self.dispatchQueue.async {
			if self.state == .active || self.state == .startingUp { return }			//already scanning
			if self.state == .shuttingDown { self.internalState = .cycling }
			if self.state == .cycling { return }
			
			self.setupCBCentral()
			
			self.oldPeripherals = self.oldPeripherals.union(self.peripherals.union(self.ignoredPeripherals))
			self.ignoredPeripherals = Set<BTLEPeripheral>()
			self.peripherals = Set<BTLEPeripheral>()
			
			if let duration = duration { self.pendingDuration = duration }
			if self.cbCentral.state == .poweredOn {
				self.startCentralScanning()
			} else {
				self.internalState = .startingUp
			}
		}
	}
	
	var pendingDuration: TimeInterval = 0.0
	func startCentralScanning() {
		self.dispatchQueue.async {
			self.internalState = .active
			let options = BTLE.manager.monitorRSSI ? [CBCentralManagerScanOptionAllowDuplicatesKey: true] : [:]
			BTLE.debugLog(.medium, BTLE.manager.serviceIDsToScanFor.count > 0 ? "Starting scan for \(BTLE.manager.serviceIDsToScanFor)" : "Starting unfiltered scan")
			self.cbCentral.scanForPeripherals(withServices: self.coreBluetoothFilteredServices.count > 0 ? self.coreBluetoothFilteredServices : nil, options: options)
			if self.pendingDuration != 0.0 {
				btle_dispatch_main {
					self.searchTimer = Timer.scheduledTimer(timeInterval: self.pendingDuration, target: self, selector: #selector(BTLECentralManager.stopScanning), userInfo: nil, repeats: false)
				}
			}
		}
	}
	
	public func stopScanning() {
		self.dispatchQueue.async {
			self.searchTimer?.invalidate()
			if let centralManager = self.cbCentral, self.internalState == .active {
				if self.internalState != .cycling && self.internalState != .idle { self.internalState = .shuttingDown }
				centralManager.stopScan()
				if self.stateChangeCounter == 0 {
					let oldState = self.internalState
					self.internalState = .idle

					if oldState == .cycling { self.restartScanning() }
				}
			}
		}
	}
	
	public func turnOff() {
		if self.cbCentral != nil && self.state != .shuttingDown && self.state != .off {
			BTLE.debugLog(.medium, "Turning Off")
			self.stopScanning()

			self.cbCentral = nil
			if self.stateChangeCounter == 0 {
				let oldState = self.internalState
				self.internalState = .off
				
				if oldState == .cycling { self.restartScanning() }
			}
		}
	}

	//=============================================================================================
	//MARK: setup
	var stateChangeCounter = 0 { didSet { assert(stateChangeCounter >= 0, "Illegal value for stateChangeCounter") }}
	func setupCBCentral(rebuild: Bool = false) {
		if self.cbCentral == nil || rebuild {
			self.turnOff()
			
			var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: true]
			
			if BTLE.browseInBackground { options[CBCentralManagerOptionRestoreIdentifierKey] = BTLECentralManager.restoreIdentifier }
			
			self.cbCentral = CBCentralManager(delegate: self, queue: self.dispatchQueue, options: options)
			if self.cbCentral.state == .poweredOn { self.fetchConnectedPeripherals() }
		}
	}
	
	func existingPeripheral(matching peripheral: CBPeripheral) -> BTLEPeripheral? {
		for perGroup in [self.peripherals, self.ignoredPeripherals, self.pendingPeripherals] {
			for per in perGroup {
				if per.uuid == peripheral.identifier {
					return per
				}
			}
		}

		return nil
	}
	
	@discardableResult func add(peripheral: CBPeripheral, RSSI: Int? = nil, advertisementData: [String: Any]? = nil) -> BTLEPeripheral? {
		if let existing = self.existingPeripheral(matching: peripheral) {
			if let rssi = RSSI { existing.setCurrentRSSI(newRSSI: rssi) }
			if let advertisementData = advertisementData { existing.advertisementData = advertisementData }
			return existing
		}
		
		for ignoredPer in self.ignoredPeripherals {
			if ignoredPer.uuid == peripheral.identifier {
				if let info = advertisementData, ignoredPer.ignored == .missingServices {
					ignoredPer.updateIgnoredWithAdvertisingData(info: info)
					
					if ignoredPer.ignored == .not {
						self.peripherals.insert(ignoredPer)
						self.ignoredPeripherals.remove(ignoredPer)
						ignoredPer.sendNotification(name: BTLE.notifications.peripheralWasDiscovered)
						return ignoredPer
					}
				}
				return ignoredPer
			}
		}

		for oldPer in self.oldPeripherals {
			if oldPer.uuid == peripheral.identifier {
				self.oldPeripherals.remove(oldPer)
				if oldPer.ignored != .not {
					self.ignoredPeripherals.insert(oldPer)
				} else {
					self.peripherals.insert(oldPer)
					if let rssi = RSSI { oldPer.setCurrentRSSI(newRSSI: rssi) }
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
		if per.ignored != .not {
			if per.ignored != .checkingForServices {
				self.ignoredPeripherals.insert(per)
			} else {
				self.pendingPeripherals.insert(per)
			}
			return per
		} else {
			self.peripherals.insert(per)
		}
		
		per.sendNotification(name: BTLE.notifications.peripheralWasDiscovered)
		return per
	}

	func pendingPeripheralFinishLoadingServices(peripheral: BTLEPeripheral) {
		self.dispatchQueue.async {
			if peripheral.ignored == .missingServices {
				self.ignoredPeripherals.insert(peripheral)
				peripheral.sendNotification(name: BTLE.notifications.peripheralWasDiscovered)
				self.pendingPeripherals.remove(peripheral)
			} else if peripheral.ignored == .not {
				self.peripherals.insert(peripheral)
				peripheral.sendNotification(name: BTLE.notifications.peripheralWasDiscovered)
				self.pendingPeripherals.remove(peripheral)
			}
		}
	}
	
	//=============================================================================================
	//MARK: CBCentralManagerDelegate
	public func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
		self.dispatchQueue.async {
			BTLE.debugLog(.medium, "Central manager updated state to \(centralManager.state.rawValue), my state: \(self.internalState)")
			switch centralManager.state {
			case .poweredOn:
				if self.internalState == .powerInterupted {
					self.internalState = .active
				} else if self.internalState == .startingUp {
					self.internalState = .active
				}
				self.fetchConnectedPeripherals()

			case .poweredOff:
				if self.internalState == .active || self.internalState == .startingUp {
					self.internalState = .powerInterupted
					self.stopScanning()
				} else {
					self.internalState = .off
				}
			default: break
			}
		}

	}
	
	public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
		self.dispatchQueue.async {
			self.add(peripheral: peripheral, RSSI: RSSI.intValue as BTLEPeripheral.RSSValue, advertisementData: advertisementData)
		}
	}
	
	public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
		self.dispatchQueue.async {
			self.cbCentral = central
			central.delegate = self
			if self.cbCentral.state == .poweredOn { self.fetchConnectedPeripherals() }
		}
	}

	public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		self.dispatchQueue.async {
			if BTLE.debugLevel.rawValue > DebugLevel.none.rawValue {
				BTLE.debugLog(.medium, "Failed to connect to peripheral: \(peripheral): \(error)")
			}
			if let existing = self.existingPeripheral(matching: peripheral) {
				existing.didFailToConnect(error: error)
			}
		}
	}
	
	public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		self.dispatchQueue.async {
			if let per = self.add(peripheral: peripheral), per.state != .connected {
				per.state = .connected
				per.sendNotification(name: BTLE.notifications.peripheralDidConnect)
			}
		}
	}
	
	public func centralManager(_ centralManager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		self.dispatchQueue.async {
			if let per = self.add(peripheral: peripheral), per.state != .discovered {
				per.state = .discovered
				per.sendNotification(name: BTLE.notifications.peripheralDidDisconnect)
			}
		}
	}
	
	//=============================================================================================
	//MARK: Utility
	
	func fetchConnectedPeripherals() {
		self.dispatchQueue.async {
			if let connected = self.cbCentral?.retrieveConnectedPeripherals(withServices: self.coreBluetoothFilteredServices) {
				for peripheral in connected {
					self.add(peripheral: peripheral)
				}
				self.internalState = .active
			}
		}
	}

	//=============================================================================================
	//MARK: Ignored Devices
	let ignoredPeripheralUUIDsKey = DefaultsKey<[String]>("ignored-btle-uuids")
	lazy var ignoredPeripheralUUIDs: Set<String> = {
		let list = UserDefaults.get(key: self.ignoredPeripheralUUIDsKey)
		
		if list.count > 0 { BTLE.debugLog(.low, "Ignored IDs: " + NSArray(array: list).componentsJoined(by: ", ")) }
		
		return Set(list)
	}()
	func addIgnored(peripheral: BTLEPeripheral) {
		self.peripherals.remove(peripheral)
		self.ignoredPeripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.insert(peripheral.uuid.uuidString)
		UserDefaults.set(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func removeIgnored(peripheral: BTLEPeripheral) {
		self.ignoredPeripherals.remove(peripheral)
		self.peripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.remove(peripheral.uuid.uuidString)
		UserDefaults.set(Array(self.ignoredPeripheralUUIDs), forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func isIgnored(peripheral: BTLEPeripheral) -> Bool {
		return self.ignoredPeripherals.contains(peripheral) || self.ignoredPeripheralUUIDs.contains(peripheral.uuid.uuidString)
	}

}
