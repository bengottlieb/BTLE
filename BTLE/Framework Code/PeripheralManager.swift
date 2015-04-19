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
	var cbPeripheralManager: CBPeripheralManager!
	var advertisingData: [NSObject: AnyObject] = [CBAdvertisementDataLocalNameKey: UIDevice.currentDevice().name]
	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return NSBundle.mainBundle().infoDictionary?["CFBundleIdentifier"] as? String ?? "ident" }

	
	//=============================================================================================
	//MARK: Actions
	
	public func startAdvertising() {
		self.setupCBPeripheralManager()
		
		if self.cbPeripheralManager.state == .PoweredOn {
			self.setupAdvertising()
		} else {
			BTLE.manager.advertisingState = .StartingUp
		}
	}

	
	public func stopAdvertising() {
		if !self.changingState {
			if BTLE.manager.advertisingState == .Off { return }
		}
		self.cbPeripheralManager.stopAdvertising()

		BTLE.manager.advertisingState == .Off
	}
	
	//=============================================================================================
	//MARK: BTLEPeripheralDelegate
	public func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager!) {
		switch cbPeripheralManager.state {
		case .PoweredOn:
			for service in self.services {
				self.cbPeripheralManager.addService(service.cbService as! CBMutableService)
			}
			self.setupAdvertising()
		default: break
		}
	}

	
	public func peripheralManager(peripheral: CBPeripheralManager!, willRestoreState dict: [NSObject : AnyObject]!) {
		
		
	}
	
	//=============================================================================================
	//MARK: Private
	
	
	//=============================================================================================
	//MARK: setup
	var changingState = false
	func setupCBPeripheralManager(rebuild: Bool = false) {
		if self.cbPeripheralManager == nil || rebuild {
			self.turnOff()
			
			var options: [NSObject: AnyObject] = [CBPeripheralManagerOptionRestoreIdentifierKey: BTLEPeripheralManager.restoreIdentifier]
			
			self.cbPeripheralManager = CBPeripheralManager(delegate: self, queue: self.dispatchQueue, options: options)
		}
	}
	
	func setupAdvertising() {
		self.cbPeripheralManager.startAdvertising(self.advertisingData)
	}

	func turnOff() {
		self.stopAdvertising()
		
		if let peripheralManager = self.cbPeripheralManager {
			self.cbPeripheralManager = nil
			if !self.changingState { BTLE.manager.scanningState = .Off }
		}
		
		
	}
	
	public var services: [BTLEMutableService] = []
	
	public func addService(service: BTLEMutableService) {
		self.setupCBPeripheralManager()
		self.services.append(service)
		if self.cbPeripheralManager.state == .PoweredOn {
			self.cbPeripheralManager.addService(service.cbService as! CBMutableService)
		}
	}

}