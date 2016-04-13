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
	public var dispatchQueue = dispatch_queue_create("BTLE.PeripheralManager queue", DISPATCH_QUEUE_SERIAL)
	public var cbPeripheralManager: CBPeripheralManager?
	public var advertisingData: [String: AnyObject] = [CBAdvertisementDataLocalNameKey: UIDevice.currentDevice().name]
	
	//=============================================================================================
	//MARK: Class vars
	class var restoreIdentifier: String { return (NSBundle.mainBundle().infoDictionary?["CFBundleIdentifier"] as? String ?? "btle") + "-advertiser" }

	
	//=============================================================================================
	//MARK: Actions
	
	public var state: BTLE.State { get { return self.internalState }}
	var internalState: BTLE.State = .Off { didSet {
		if oldValue == self.internalState { return }
		
		self.stateChangeCounter += 1
		
		switch self.internalState {
		case .Off:
			if oldValue != .Idle { NSNotification.postNotification(BTLE.notifications.didFinishAdvertising, object: self) }
			if BTLE.manager.cyclingAdvertising {
				btle_delay(0.5) {
					BTLE.manager.cyclingAdvertising = false
					self.internalState = .Active
				}
			}
		case .StartingUp:
			NSNotification.postNotification(BTLE.notifications.willStartAdvertising, object: self)
			break
			
		case .Active:
			break
			
		case .Idle:
			NSNotification.postNotification(BTLE.notifications.didFinishAdvertising, object: self)
			self.stopAdvertising()
			
		case .PowerInterupted: break
		case .Cycling: break
		case .ShuttingDown: break
		}
		
		self.stateChangeCounter -= 1
	}}
	
	
	public func startAdvertising() {
		if let mgr = self.setupCBPeripheralManager() {
			if mgr.state == .PoweredOn {
				self.setupAdvertising()
			} else {
				self.internalState = .StartingUp
			}
		}
	}

	
	public func stopAdvertising() {
		if self.stateChangeCounter == 0 {
			if self.internalState == .Off { return }
		}
		
		self.cbPeripheralManager?.stopAdvertising()

		if self.internalState == .Active || self.internalState == .StartingUp {
			self.internalState = .Idle
		}
	}
	
	//=============================================================================================
	//MARK: BTLEPeripheralDelegate
	public func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
		switch cbPeripheralManager?.state ?? .Unknown {
		case .PoweredOn:
			if self.internalState == .PowerInterupted {
				self.internalState = .Active
			}
			
			if self.internalState == .StartingUp {
				self.setupAdvertising()
			} else {
				self.internalState = .Active
			}
			self.updateServices()
			
		case .PoweredOff:
			if self.internalState == .Active || self.internalState == .StartingUp {
				self.internalState = .PowerInterupted
				self.stopAdvertising()
			}
			
		default: break
		}
	}
	
	public func peripheralManager(peripheral: CBPeripheralManager, willRestoreState dict: [String : AnyObject]) {
		let advertised = ((dict["kCBRestoredAdvertisement"] as? [NSObject: AnyObject])?["kCBAdvDataServiceUUIDs"] as? [NSData]) ?? []
		var advertisedIDs: [CBUUID] = []
		for data in advertised {
			advertisedIDs.append(CBUUID(data: data))
		}
		
		
		if let existingServices = dict["kCBRestoredServices"] as? [CBMutableService] {
			var servicesToAdd = existingServices
			
			for service in self.services {
				for existingService in existingServices {
					if service.uuid == existingService.UUID	{
						service.replaceCBService(existingService)
						servicesToAdd.remove(existingService)
					}
				}
			}
			
			for service in servicesToAdd {
				let ourService = BTLEMutableService(service: service, isAdvertised: advertisedIDs.contains(service.UUID))
				self.services.append(ourService)
			}
		}
	}
	
	public func peripheralManager(peripheral: CBPeripheralManager, didReceiveReadRequest request: CBATTRequest) {
		if let characteristic = self.characteristicWithCBCharacteristic(request.characteristic) {
			if let data = characteristic.dataValue {
				let range = NSRange(location: request.offset, length: data.length - request.offset)
				request.value = characteristic.dataValue?.subdataWithRange(range)
				self.cbPeripheralManager?.respondToRequest(request, withResult: .Success)
			} else {
				self.cbPeripheralManager?.respondToRequest(request, withResult: .Success)
			}
		}
		
		self.cbPeripheralManager?.respondToRequest(request, withResult: .AttributeNotFound)
	}
	
	public func peripheralManager(peripheral: CBPeripheralManager, didReceiveWriteRequests requests: [CBATTRequest]) {
		if requests.count == 0 { return }
		for request in requests {
			NSNotification.postNotification(BTLE.notifications.characteristicWasWrittenTo, object: self.characteristicWithCBCharacteristic(request.characteristic))
		}
		self.cbPeripheralManager?.respondToRequest(requests[0], withResult: .Success)
	}
	
	//=============================================================================================
	//MARK: Delegate - status

	
	public func peripheralManagerDidStartAdvertising(peripheral: CBPeripheralManager, error: NSError?) {
		if let error = error {
			BTLE.debugLog(.Low, "advertising started with error: \(error)")
			self.internalState = .Idle
		}
	}
	
	public func peripheralManager(peripheral: CBPeripheralManager, didAddService service: CBService, error: NSError?) {
		self.serviceWithCBService(service)?.isLive = true
	}
	
	//=============================================================================================
	//MARK: Delegate - Characteristic

	
	public func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didSubscribeToCharacteristic characteristic: CBCharacteristic) {
		
	}
	
	public func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFromCharacteristic characteristic: CBCharacteristic) {
		
	}
	
	//=============================================================================================
	//MARK: Private
	var combinedAdvertisementData: [String: AnyObject] {
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
			
			var options: [String: AnyObject] = [:]
			
			if BTLE.advertiseInBackground { options[CBPeripheralManagerOptionRestoreIdentifierKey] = BTLEPeripheralManager.restoreIdentifier }
			
			self.cbPeripheralManager = CBPeripheralManager(delegate: self, queue: self.dispatchQueue, options: options)
		}
		
		return self.cbPeripheralManager
	}
	
	func setupAdvertising() {
		if let mgr = self.cbPeripheralManager {
			if !mgr.isAdvertising && mgr.state == .PoweredOn && self.internalState != .Active {
				mgr.startAdvertising(self.combinedAdvertisementData)
				
				BTLE.debugLog(.Medium, "Starting to advertise: \(self.combinedAdvertisementData)") 
			}
		}
	}

	func turnOff() {
		self.stopAdvertising()
		
		if self.cbPeripheralManager != nil {
			self.cbPeripheralManager = nil
			if stateChangeCounter == 0 { self.internalState = .Off }
		}
		
		
	}
	
	func serviceWithCBService(service: CBService) -> BTLEMutableService? {
		for svc in self.services {
			if svc.cbService == service { return svc }
		}
		return nil
	}
	
	func characteristicWithCBCharacteristic(characteristic: CBCharacteristic) -> BTLEMutableCharacteristic? {
		if let svc = self.serviceWithCBService(characteristic.service) {
			for chr in svc.characteristics {
				if chr.cbCharacteristic == characteristic { return chr as? BTLEMutableCharacteristic }
			}
		}
		return nil
	}
	
	func updateServices() {
		dispatch_async(self.dispatchQueue) {
			if let mgr = self.cbPeripheralManager where mgr.state == .PoweredOn {
				for service in self.services { service.addToManager(self.cbPeripheralManager) }
			}
		}
	}
	
	public var services: [BTLEMutableService] = []
	
	public func addService(service: BTLEMutableService) -> BTLEMutableService {
		for existing in self.services {
			if service.uuid == existing.uuid { return existing }
		}
		self.services.append(service)
		self.updateServices()
		return service
	}
	
	public func removeService(service: BTLEMutableService) {
		service.removeFromManager(self.cbPeripheralManager)
		self.services.remove(service)
	}

}