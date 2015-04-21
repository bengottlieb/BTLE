//
//  PeripheralManager.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/17/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

public class BTLEPeripheralManager: NSObject, CBPeripheralManagerDelegate {
	var dispatchQueue = dispatch_queue_create("BTLE.PeripheralManager queue", DISPATCH_QUEUE_SERIAL)
	var cbPeripheralManager: CBPeripheralManager?
	var advertisingData: [NSObject: AnyObject] = [CBAdvertisementDataLocalNameKey: UIDevice.currentDevice().name]
	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return NSBundle.mainBundle().infoDictionary?["CFBundleIdentifier"] as? String ?? "ident" }

	
	//=============================================================================================
	//MARK: Actions
	
	public func startAdvertising() {
		if let mgr = self.setupCBPeripheralManager() {
			if mgr.state == .PoweredOn {
				self.setupAdvertising()
			} else {
				BTLE.manager.advertisingState = .StartingUp
			}
		}
	}

	
	public func stopAdvertising() {
		if self.stateChangeCounter == 0 {
			if BTLE.manager.advertisingState == .Off { return }
		}
		self.cbPeripheralManager?.stopAdvertising()

		BTLE.manager.advertisingState == .Off
		NSNotification.postNotification(BTLE.notifications.didFinishAdvertising)
	}
	
	//=============================================================================================
	//MARK: BTLEPeripheralDelegate
	public func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager!) {
		switch cbPeripheralManager?.state ?? .Unknown {
		case .PoweredOn:
			if BTLE.manager.advertisingState == .PowerInterupted {
				BTLE.manager.scanningState = .Active
			}
			for service in self.services {
				service.addToPeripheralManager(self.cbPeripheralManager)
			}
			
			if BTLE.manager.advertisingState == .StartingUp {
				self.setupAdvertising()
			} else {
				BTLE.manager.advertisingState = .Idle
			}
			
		case .PoweredOff:
			if BTLE.manager.advertisingState == .Active || BTLE.manager.advertisingState == .StartingUp {
				BTLE.manager.advertisingState = .PowerInterupted
				self.stopAdvertising()
			}
			
		default: break
		}
	}

	
	public func peripheralManager(peripheral: CBPeripheralManager!, willRestoreState dict: [NSObject : AnyObject]!) {
		
		
	}
	
	public func peripheralManagerDidStartAdvertising(peripheral: CBPeripheralManager!, error: NSError!) {
		if BTLE.debugging { println("advertising started with error: \(error)") }
	}
	
	//=============================================================================================
	//MARK: Private
	var combinedAdvertisementData: [NSObject: AnyObject] {
		var data = self.advertisingData
		var services: [CBUUID] = []
		
		for service in self.services {
			if service.advertised { services.append(service.uuid) }
		}
		
		if services.count > 0 { data[CBAdvertisementDataServiceUUIDsKey] = NSArray(array: services) }
		
		return data
	}
	
	//=============================================================================================
	//MARK: setup
	var stateChangeCounter = 0 { didSet { assert(stateChangeCounter >= 0, "Illegal value for stateChangeCounter") }}
	func setupCBPeripheralManager(rebuild: Bool = false) -> CBPeripheralManager? {
		if self.cbPeripheralManager == nil || rebuild {
			self.turnOff()
			
			var options: [NSObject: AnyObject] = [CBPeripheralManagerOptionRestoreIdentifierKey: BTLEPeripheralManager.restoreIdentifier]
			
			self.cbPeripheralManager = CBPeripheralManager(delegate: self, queue: self.dispatchQueue, options: options)
		}
		
		return self.cbPeripheralManager
	}
	
	func setupAdvertising() {
		if let mgr = self.cbPeripheralManager {
			if !mgr.isAdvertising && mgr.state == .PoweredOn {
				NSNotification.postNotification(BTLE.notifications.willStartAdvertising)
				mgr.startAdvertising(self.combinedAdvertisementData)
				
				if BTLE.debugging { println("Starting to advertise: \(self.combinedAdvertisementData)") }
			}
		}
	}

	func turnOff() {
		self.stopAdvertising()
		
		if let peripheralManager = self.cbPeripheralManager {
			self.cbPeripheralManager = nil
			if stateChangeCounter == 0 { BTLE.manager.scanningState = .Off }
		}
		
		
	}
	
	public var services: [BTLEMutableService] = []
	
	public func addService(service: BTLEMutableService) {
		self.services.append(service)
		if let mgr = self.cbPeripheralManager where mgr.state == .PoweredOn {
			mgr.addService(service.cbService as! CBMutableService)
		}
	}

}