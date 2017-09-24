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
	public var dispatchQueue = DispatchQueue(label: "BTLEManager.CentralManager queue")
	public var cbCentral: CBCentralManager!

	public var peripherals = Set<BTLEPeripheral>()
	public var ignoredPeripherals = Set<BTLEPeripheral>()
	public var oldPeripherals = Set<BTLEPeripheral>()
	var pendingPeripherals = Set<BTLEPeripheral>()
	
	public private (set) var state: BTLEManager.State = .off { didSet {
		if oldValue == self.state { return }
		
		BTLEManager.debugLog(.medium, "Changing state to \(self.state) from \(oldValue), Central state: \(self.cbCentral?.state.rawValue ?? -1)")
		self.stateChangeCounter += 1
		
		switch self.state {
		case .off:
			Notification.postOnMainThread(name: BTLEManager.notifications.didFinishScan, object: self)
			break
			
		case .startingUp:
			Notification.postOnMainThread(name: BTLEManager.notifications.willStartScan, object: self)
			if self.cbCentral?.state == .poweredOn {
				self.state = .active
			}
			break
			
		case .active:
			self.startCentralScanning()
			Notification.postOnMainThread(name: BTLEManager.notifications.didStartScan, object: self)
			
		case .idle:
			Notification.postOnMainThread(name: BTLEManager.notifications.didFinishScan, object: self)
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
	
	
	func serialize(block: @escaping () -> Void) {
		if Thread.isMainThread {
			block()
		} else {
			DispatchQueue.main.sync(execute: block)
		}
//		self.dispatchQueue.sync(execute: block)
	}
	
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
		BTLEManager.debugLog(.medium, "Cleared out \(count) devices")
	}
	
	func cycle() {
		if self.state == .active {
			BTLEManager.debugLog(.low, "Cycling Services")
			self.state = .cycling
		}
	}
	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return (Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String ?? "btle") + "-scanner" }

	
	//=============================================================================================
	//MARK: State changers
	weak var searchTimer: Timer?
	
	var coreBluetoothFilteredServices: [CBUUID] { return BTLEManager.instance.serviceFilter == .coreBluetooth ? BTLEManager.instance.serviceIDsToScanFor : [] }
	
	func restartScanning() {
		self.state = .idle
		self.startScanning()
	}
	
	public func startScanning(for duration: TimeInterval? = nil) {
		self.serialize {
			if self.state == .active || self.state == .startingUp { return }			//already scanning
			if self.state == .shuttingDown { self.state = .cycling }
			if self.state == .cycling { return }
			
			self.setupCBCentral()
			
			self.oldPeripherals = self.oldPeripherals.union(self.peripherals.union(self.ignoredPeripherals))
			self.ignoredPeripherals = Set<BTLEPeripheral>()
			self.peripherals = Set<BTLEPeripheral>()
			
			if let duration = duration { self.pendingDuration = duration }
			if self.cbCentral.state == .poweredOn {
				self.state = .active
			} else {
				self.state = .startingUp
			}
		}
	}
	
	var pendingDuration: TimeInterval = 0.0
	func startCentralScanning() {
		self.serialize {
			BTLEManager.debugLog(.medium, BTLEManager.instance.serviceIDsToScanFor.count > 0 ? "Starting scan for \(BTLEManager.instance.serviceIDsToScanFor)" : "Starting unfiltered scan")

			let options = BTLEManager.instance.monitorRSSI ? [CBCentralManagerScanOptionAllowDuplicatesKey: true] : [:]
			self.cbCentral.scanForPeripherals(withServices: self.coreBluetoothFilteredServices.count > 0 ? self.coreBluetoothFilteredServices : nil, options: options)
			if self.pendingDuration != 0.0 {
				DispatchQueue.main.async {
					self.searchTimer = Timer.scheduledTimer(timeInterval: self.pendingDuration, target: self, selector: #selector(BTLECentralManager.stopScanning), userInfo: nil, repeats: false)
				}
			}
		}
	}
	
	public func stopScanning() {
		self.serialize {
			self.searchTimer?.invalidate()
			if let centralManager = self.cbCentral, self.state == .active {
				if self.state != .cycling && self.state != .idle { self.state = .shuttingDown }
				centralManager.stopScan()
				if self.stateChangeCounter == 0 {
					let oldState = self.state
					self.state = .idle

					if oldState == .cycling { self.restartScanning() }
				}
			}
		}
	}
	
	public func turnOff() {
		if self.cbCentral != nil && self.state != .shuttingDown && self.state != .off {
			BTLEManager.debugLog(.medium, "Turning Off")
			self.stopScanning()

			self.cbCentral = nil
			if self.stateChangeCounter == 0 {
				let oldState = self.state
				self.state = .off
				
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
			
			if BTLEManager.browseInBackground { options[CBCentralManagerOptionRestoreIdentifierKey] = BTLECentralManager.restoreIdentifier }
			
			self.cbCentral = CBCentralManager(delegate: self, queue: self.dispatchQueue, options: options)
			if self.cbCentral.state == .poweredOn { self.fetchConnectedPeripherals() }
		}
	}
	
	func existingPeripheral(matching peripheral: CBPeripheral) -> BTLEPeripheral? { return self.existingPeripheral(with: peripheral.identifier) }
	
	func existingPeripheral(with id: UUID) -> BTLEPeripheral? {
		for per in [self.peripherals, self.ignoredPeripherals, self.pendingPeripherals].flatMap({ $0 }) {
			if per.uuid == id {
				return per
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
						ignoredPer.sendNotification(name: BTLEManager.notifications.peripheralWasDiscovered)
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
		
		if let perClass = BTLEManager.registeredClasses.peripheralClass {
			per = perClass.init(peripheral: peripheral, RSSI: RSSI, advertisementData: advertisementData)
		} else {
			if BTLEManager.instance.ignoreBeaconLikeDevices, let _ = advertisementData?[CBAdvertisementDataManufacturerDataKey] {
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
		
		per.sendNotification(name: BTLEManager.notifications.peripheralWasDiscovered)
		return per
	}

	func pendingPeripheralFinishLoadingServices(peripheral: BTLEPeripheral) {
		self.serialize {
			if peripheral.ignored == .missingServices {
				self.ignoredPeripherals.insert(peripheral)
				peripheral.sendNotification(name: BTLEManager.notifications.peripheralWasDiscovered)
				self.pendingPeripherals.remove(peripheral)
			} else if peripheral.ignored == .not {
				self.peripherals.insert(peripheral)
				peripheral.sendNotification(name: BTLEManager.notifications.peripheralWasDiscovered)
				self.pendingPeripherals.remove(peripheral)
			}
		}
	}
	
	//=============================================================================================
	//MARK: CBCentralManagerDelegate
	public func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
		self.serialize {
			BTLEManager.debugLog(.medium, "Central manager updated state to \(centralManager.state.rawValue), my state: \(self.state)")
			switch centralManager.state {
			case .poweredOn:
				if self.state == .powerInterupted {
					self.state = .active
				} else if self.state == .startingUp {
					self.state = .active
				}
				self.fetchConnectedPeripherals()

			case .poweredOff:
				if self.state == .active || self.state == .startingUp {
					self.state = .powerInterupted
					self.stopScanning()
				} else {
					self.state = .off
				}
			default: break
			}
		}

	}
	
	public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
	//	self.serialize {
			self.add(peripheral: peripheral, RSSI: RSSI.intValue as BTLEPeripheral.RSSValue, advertisementData: advertisementData)
	//	}
	}
	
	public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		BTLEManager.debugLog(.medium, "Failed to connect to peripheral: \(peripheral): \(error?.localizedDescription ?? "")")
		self.serialize {
			if let existing = self.existingPeripheral(matching: peripheral) {
				existing.didFailToConnect(error: error)
			}
		}
	}
	
	public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		BTLEManager.debugLog(.high, "Connected to peripheral: \(peripheral)")
		self.serialize {
			if let per = self.add(peripheral: peripheral), per.state != .connected {
				per.state = .connected
				per.sendNotification(name: BTLEManager.notifications.peripheralDidConnect)
			}
		}
	}
	
	public func centralManager(_ centralManager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		self.serialize {
			if let per = self.add(peripheral: peripheral), per.state != .discovered {
				BTLEManager.debugLog(.medium, "Disconnected from: \(peripheral): \(error?.localizedDescription ?? "")")
				per.state = .discovered
				per.sendNotification(name: BTLEManager.notifications.peripheralDidDisconnect)
			}
		}
	}
	
	//=============================================================================================
	//MARK: Utility
	
	func fetchConnectedPeripherals() {
		self.serialize {
			let alreadyConnected: [CBPeripheral] = self.cbCentral.retrieveConnectedPeripherals(withServices: self.coreBluetoothFilteredServices)
			
			BTLEManager.debugLog(.medium, "Loading already-connected devices: \(alreadyConnected).")
			for peripheral in alreadyConnected {
				self.add(peripheral: peripheral)
			}
			self.state = .active
		}
	}

	//=============================================================================================
	//MARK: Ignored Devices
	let ignoredPeripheralUUIDsKey = DefaultsKey<String>("ignored-btle-device-uuids")
	lazy var ignoredPeripheralUUIDs: Set<String> = {
		guard let raw: String = UserDefaults.get(self.ignoredPeripheralUUIDsKey) else { return Set<String>() }
		let list = raw.components(separatedBy: ",")
		
		if list.count > 0 { BTLEManager.debugLog(.low, "Ignored IDs: " + NSArray(array: list).componentsJoined(by: ", ")) }
		
		return Set(list)
	}()
	func addIgnored(peripheral: BTLEPeripheral) {
		self.peripherals.remove(peripheral)
		self.ignoredPeripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.insert(peripheral.uuid.uuidString)
		let list = Array(self.ignoredPeripheralUUIDs).joined(separator: ",")
		UserDefaults.set(list, forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func removeIgnored(peripheral: BTLEPeripheral) {
		self.ignoredPeripherals.remove(peripheral)
		self.peripherals.insert(peripheral)
		
		self.ignoredPeripheralUUIDs.remove(peripheral.uuid.uuidString)
		let list = Array(self.ignoredPeripheralUUIDs).joined(separator: ",")
		UserDefaults.set(list, forKey: self.ignoredPeripheralUUIDsKey)
	}
	
	func isIgnored(peripheral: BTLEPeripheral) -> Bool {
		return self.ignoredPeripherals.contains(peripheral) || self.ignoredPeripheralUUIDs.contains(peripheral.uuid.uuidString)
	}

}

class BTLEBackgroundableCentralManager: BTLECentralManager {
	public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
		self.serialize {
			self.cbCentral = central
			central.delegate = self
			if self.cbCentral.state == .poweredOn { self.fetchConnectedPeripherals() }
		}
	}
}
