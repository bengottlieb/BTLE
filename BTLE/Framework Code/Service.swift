//
//  Service.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

protocol ServiceProtocol {
	init();
	init(service svc: CBService, onPeriperhal: Peripheral);
}

public class Service: NSObject, Printable, ServiceProtocol {
	public var cbService: CBService!
	var peripheral: Peripheral!
	var loading = false
	public var characteristics: [Characteristic] = []
	var pendingCharacteristics: [Characteristic] = []
	
	class func createService(service svc: CBService, onPeriperhal: Peripheral) -> Service {
		if let serviceClass: Service.Type = BTLE.registeredClasses.services[svc.UUID] {
			return serviceClass(service: svc, onPeriperhal: onPeriperhal)
		} else {
			return Service(service: svc, onPeriperhal: onPeriperhal)
		}
	}
	
	public override required init() {
		super.init()
	}
	
	public required init(service svc: CBService, onPeriperhal: Peripheral) {
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
				self.characteristics.append(Characteristic.characteristic(chr, ofService: self))
			}
		}
	}
	
	public func didFinishLoading() {
		self.loading = false
		self.peripheral.didFinishLoadingService(self)
	}
	
	func findCharacteristicMatching(chr: CBCharacteristic) -> Characteristic? {
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
	
	public func characteristicWithUUID(uuid: CBUUID) -> Characteristic? { return filter(self.characteristics, { $0.cbCharacteristic.UUID == uuid }).last }
	
}
