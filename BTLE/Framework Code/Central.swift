//
//  Central.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth
import SA_Swift

public class Central: NSObject, CBCentralManagerDelegate {
	var dispatchQueue = dispatch_queue_create("BTLE.Central queue", DISPATCH_QUEUE_SERIAL)
	var cbCentral: CBCentralManager!
	
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
		if let central = self.cbCentral {
			central.stopScan()
			NSNotification.postNotification(BTLE.notifications.didFinishScan, object: self)
			if !self.changingState { BTLE.manager.state = .Off }
		}
	}
	
	func turnOff() {
		self.stopScanning()

		if let central = self.cbCentral {
			self.cbCentral = nil
			if !self.changingState { BTLE.manager.state = .Off }
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
			
			var options: [NSObject: AnyObject] = [CBCentralManagerOptionShowPowerAlertKey: true, CBCentralManagerOptionRestoreIdentifierKey: Central.restoreIdentifier]
			
			self.cbCentral = CBCentralManager(delegate: self, queue: self.dispatchQueue, options: options)
			if self.cbCentral.state == .PoweredOn { self.fetchConnectedPeripherals() }
		}
	}
	
	func addPeripheral(peripheral: CBPeripheral, RSSI: Int? = nil, advertisementData: [NSObject: AnyObject]? = nil) -> Peripheral {
		for per in BTLE.manager.peripherals {
			if per.uuid == peripheral.identifier {
				if let rssi = RSSI { per.rssi = rssi }
				if let advertisementData = advertisementData { per.advertisementData = advertisementData }
				return per
			}
		}
		
		let per: Peripheral
		
		if let perClass = BTLE.registeredClasses.peripheralClass {
			per = perClass(peripheral: peripheral, RSSI: RSSI, advertisementData: advertisementData)
		} else {
			per = Peripheral(peripheral: peripheral, RSSI: RSSI, advertisementData: advertisementData)
		}
		BTLE.manager.peripherals.append(per)
		
		NSNotification.postNotification(BTLE.notifications.didDiscoverPeripheral, object: per)
		return per
	}


	//=============================================================================================
	//MARK: CBCentralManagerDelegate
	public func centralManagerDidUpdateState(central: CBCentralManager!) {
		switch central.state {
		case .PoweredOn: self.fetchConnectedPeripherals()
		default: break
		}

	}
	
	public func centralManager(central: CBCentralManager!, didDiscoverPeripheral peripheral: CBPeripheral!, advertisementData: [NSObject : AnyObject]!, RSSI: NSNumber!) {
		var per = self.addPeripheral(peripheral, RSSI: RSSI.integerValue, advertisementData: advertisementData)
	}
	
	public func centralManager(central: CBCentralManager!, willRestoreState dict: [NSObject : AnyObject]!) {
		self.cbCentral = central
		central.delegate = self
		if self.cbCentral.state == .PoweredOn { self.fetchConnectedPeripherals() }
	}
	
	public func centralManager(central: CBCentralManager!, didConnectPeripheral peripheral: CBPeripheral!) {
		var per = self.addPeripheral(peripheral)
		per.state = .Connected
		NSNotification.postNotification(BTLE.notifications.peripheralDidConnect, object: per)
	}
	
	public func centralManager(central: CBCentralManager!, didDisconnectPeripheral peripheral: CBPeripheral!, error: NSError!) {
		var per = self.addPeripheral(peripheral)
		per.state = .Discovered
		NSNotification.postNotification(BTLE.notifications.peripheralDidDisconnect, object: per)
	}
	
	//=============================================================================================
	//MARK: Utility
	
	func fetchConnectedPeripherals() {
		var connected = self.cbCentral.retrieveConnectedPeripheralsWithServices(BTLE.manager.services) as! [CBPeripheral]
		for peripheral in connected {
			self.addPeripheral(peripheral)
		}
		BTLE.manager.state = .Scanning
	}


}