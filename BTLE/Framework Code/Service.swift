//
//  Service.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

public class Service: NSObject, Printable {
	public let cbService: CBService
	let peripheral: Peripheral
	var loading = false
	public var characteristics: [Characteristic] = []
	var pendingCharacteristics: [Characteristic] = []
	
	init(service svc: CBService, onPeriperhal: Peripheral) {
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
				self.loading = false
				self.peripheral.didFinishLoadingService(self)
			}
			NSNotification.postNotification(BTLE.notifications.characteristicDidUpdate, object: char, userInfo: nil)
		}
	}
	
	public override var description: String { return "\(self.cbService): \(self.characteristics)" }
	
	func characteristicWithUUID(uuid: CBUUID) -> Characteristic? { return filter(self.characteristics, { $0.cbCharacteristic.UUID == uuid }).last }
	
}
