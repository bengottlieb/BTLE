//
//  BTLEService.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

protocol BTLEServiceProtocol {
	init();
	init(service svc: CBService, onPeriperhal: BTLEPeripheral);
}

public class BTLEService: NSObject, Printable, BTLEServiceProtocol {
	public var cbService: CBService!
	var peripheral: BTLEPeripheral!
	var loading = false
	public var characteristics: [BTLECharacteristic] = []
	var pendingCharacteristics: [BTLECharacteristic] = []
	
	class func createService(service svc: CBService, onPeriperhal: BTLEPeripheral) -> BTLEService {
		if let serviceClass: BTLEService.Type = BTLE.registeredClasses.services[svc.UUID] {
			return serviceClass(service: svc, onPeriperhal: onPeriperhal)
		} else {
			return BTLEService(service: svc, onPeriperhal: onPeriperhal)
		}
	}
	
	public override required init() {
		super.init()
	}
	
	public required init(service svc: CBService, onPeriperhal: BTLEPeripheral) {
		cbService = svc
		peripheral = onPeriperhal
		super.init()
		
		self.load()
	}
	
	func load() {
		if !self.loading {
			self.loading = true
			
			self.peripheral.cbPeripheral.discoverCharacteristics(nil, forService: self.cbService)
		}
	}
	
	func updateCharacteristics() {
		for chr in self.cbService.characteristics as! [CBCharacteristic] {
			if self.findCharacteristicMatching(chr) == nil {
				self.characteristics.append(BTLECharacteristic.characteristic(chr, ofService: self))
			}
		}
	}
	
	public func didFinishLoading() {
		self.loading = false
		self.peripheral.didFinishLoadingService(self)
	}
	
	func findCharacteristicMatching(chr: CBCharacteristic) -> BTLECharacteristic? {
		return filter(self.characteristics, { $0.cbCharacteristic == chr }).last
	}
	
	var numberOfPendingCharacteristics: Int {
		var count = 0
		
		for chr in self.characteristics {
			if chr.loading { count++ }
		}
		return count
	}
	
	func didLoadCharacteristic(chr: CBCharacteristic) {
		//println("Loaded characteristic: \(chr)")
		if let char = self.findCharacteristicMatching(chr) {
			char.didLoad()
			if self.numberOfPendingCharacteristics == 0 {
				self.didFinishLoading()
			}
			NSNotification.postNotification(BTLE.notifications.characteristicDidUpdate, object: char, userInfo: nil)
		}
	}
	
	public override var description: String { return "\(self.cbService): \(self.characteristics)" }
	
	public func characteristicWithUUID(uuid: CBUUID) -> BTLECharacteristic? { return filter(self.characteristics, { $0.cbCharacteristic.UUID == uuid }).last }
	
}
