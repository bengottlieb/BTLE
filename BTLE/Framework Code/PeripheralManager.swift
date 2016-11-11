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
	public var dispatchQueue = DispatchQueue(label: "BTLE.PeripheralManager queue")
	public var cbPeripheralManager: CBPeripheralManager?
	public var advertisingData: [String: Any] = [CBAdvertisementDataLocalNameKey: UIDevice.current.name]
	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return (Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String ?? "btle") + "-advertiser" }

	
	//=============================================================================================
	//MARK: Actions
	
	public var state: BTLE.State { get { return self.internalState }}
	var internalState: BTLE.State = .off { didSet {
		if oldValue == self.internalState { return }
		
		self.stateChangeCounter += 1
		
		switch self.internalState {
		case .off:
			if oldValue != .idle { Notification.postOnMainThread(name: BTLE.notifications.didFinishAdvertising, object: self) }
			if BTLE.manager.cyclingAdvertising {
				btle_delay(0.5) {
					BTLE.manager.cyclingAdvertising = false
					self.internalState = .active
				}
			}
		case .startingUp:
			Notification.postOnMainThread(name: BTLE.notifications.willStartAdvertising, object: self)
			break
			
		case .active:
			break
			
		case .idle:
			Notification.postOnMainThread(name: BTLE.notifications.didFinishAdvertising, object: self)
			self.stopAdvertising()
			
		case .powerInterupted: break
		case .cycling: break
		case .shuttingDown: break
		}
		
		self.stateChangeCounter -= 1
	}}
	
	
	public func startAdvertising() {
		if let mgr = self.setupCBPeripheralManager() {
			if mgr.state == .poweredOn {
				self.setupAdvertising()
			} else {
				self.internalState = .startingUp
			}
		}
	}

	
	public func stopAdvertising() {
		if self.stateChangeCounter == 0 {
			if self.internalState == .off { return }
		}
		
		self.cbPeripheralManager?.stopAdvertising()

		if self.internalState == .active || self.internalState == .startingUp {
			self.internalState = .idle
		}
	}
	
	//=============================================================================================
	//MARK: BTLEPeripheralDelegate
	public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
		switch cbPeripheralManager?.state ?? .unknown {
		case .poweredOn:
			if self.internalState == .powerInterupted {
				self.internalState = .active
			}
			
			if self.internalState == .startingUp {
				self.setupAdvertising()
			} else {
				self.internalState = .active
			}
			self.updateServices()
			
		case .poweredOff:
			if self.internalState == .active || self.internalState == .startingUp {
				self.internalState = .powerInterupted
				self.stopAdvertising()
			}
			
		default: break
		}
	}
	
	public func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any])
 {
		let advertised = ((dict["kCBRestoredAdvertisement"] as? [String: Any])?["kCBAdvDataServiceUUIDs"] as? [NSData]) ?? []
		var advertisedIDs: [CBUUID] = []
		for data in advertised {
			advertisedIDs.append(CBUUID(data: data as Data))
		}
		
		
		if let existingServices = dict["kCBRestoredServices"] as? [CBMutableService] {
			var servicesToAdd = existingServices
			
			for service in self.services {
				for existingService in existingServices {
					if service.uuid == existingService.uuid	{
						service.replaceCBService(with: existingService)
						_ = servicesToAdd.remove(object: existingService)
					}
				}
			}
			
			for service in servicesToAdd {
				let ourService = BTLEMutableService(service: service, isAdvertised: advertisedIDs.contains(service.uuid))
				self.services.append(ourService)
			}
		}
	}
	
	public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
		if let characteristic = self.existingCharacteristic(with : request.characteristic) {
			if let data = characteristic.dataValue {
		//		let range = NSRange(location: request.offset, length: data.count - request.offset)
				request.value = data.subdata(in: request.offset..<data.count)
				self.cbPeripheralManager?.respond(to: request, withResult: .success)
			} else {
				self.cbPeripheralManager?.respond(to: request, withResult: .success)
			}
		}
		
		self.cbPeripheralManager?.respond(to: request, withResult: .attributeNotFound)
	}
	
	public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
		if requests.count == 0 { return }
		for request in requests {
			Notification.postOnMainThread(name: BTLE.notifications.characteristicWasWrittenTo, object: self.existingCharacteristic(with: request.characteristic))
		}
		self.cbPeripheralManager?.respond(to: requests[0], withResult: .success)
	}
	
	//=============================================================================================
	//MARK: Delegate - status

	
	public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
		if let error = error {
			BTLE.debugLog(.low, "advertising started with error: \(error)")
			self.internalState = .idle
		}
	}
	
	public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
		self.existingService(with: service)?.isLive = true
	}
	
	//=============================================================================================
	//MARK: Delegate - Characteristic

	
	public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
		
	}
	
	public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
		
	}
	
	//=============================================================================================
	//MARK: Private
	var combinedAdvertisementData: [String: Any] {
		var data = self.advertisingData
		var services: [CBUUID] = [] { didSet { self.updateServices() }}
		
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
			
			var options: [String: Any] = [:]
			
			if BTLE.advertiseInBackground { options[CBPeripheralManagerOptionRestoreIdentifierKey] = BTLEPeripheralManager.restoreIdentifier }
			
			self.cbPeripheralManager = CBPeripheralManager(delegate: self, queue: self.dispatchQueue, options: options)
		}
		
		return self.cbPeripheralManager
	}
	
	func setupAdvertising() {
		if let mgr = self.cbPeripheralManager {
			if !mgr.isAdvertising && mgr.state == .poweredOn && self.internalState != .active {
				mgr.startAdvertising(self.combinedAdvertisementData)
				
				BTLE.debugLog(.medium, "Starting to advertise: \(self.combinedAdvertisementData)") 
			}
		}
	}

	func turnOff() {
		self.stopAdvertising()
		
		if self.cbPeripheralManager != nil {
			self.cbPeripheralManager = nil
			if stateChangeCounter == 0 { self.internalState = .off }
		}
		
		
	}
	
	func existingService(with service: CBService) -> BTLEMutableService? {
		for svc in self.services {
			if svc.cbService == service { return svc }
		}
		return nil
	}
	
	func existingCharacteristic(with characteristic: CBCharacteristic) -> BTLEMutableCharacteristic? {
		if let svc = self.existingService(with: characteristic.service) {
			for chr in svc.characteristics {
				if chr.cbCharacteristic == characteristic { return chr as? BTLEMutableCharacteristic }
			}
		}
		return nil
	}
	
	func updateServices() {
		self.dispatchQueue.async {
			if let mgr = self.cbPeripheralManager, mgr.state == .poweredOn {
				for service in self.services { service.add(to: self.cbPeripheralManager) }
			}
		}
	}
	
	public var services: [BTLEMutableService] = []
	
	@discardableResult public func add(service: BTLEMutableService) -> BTLEMutableService {
		for existing in self.services {
			if service.uuid == existing.uuid { return existing }
		}
		self.services.append(service)
		self.updateServices()
		return service
	}
	
	public func remove(service: BTLEMutableService) {
		service.remove(from: self.cbPeripheralManager)
		_ = self.services.remove(object: service)
	}

}
