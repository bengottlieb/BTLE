//
//  Characteristic.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

public class Characteristic: NSObject {
	public let cbCharacteristic: CBCharacteristic
	public let service: Service
	var loading = false
	
	var peripheral: Peripheral { return self.service.peripheral }
	
	class func characteristic(chr: CBCharacteristic, ofService: Service) -> Characteristic {
	//	if chr.UUID == LockStatusCharacteristic { return BTLELockStatusCharacteristic(characteristic: chr, ofService: ofService) }
		
		return Characteristic(characteristic: chr, ofService: ofService)
	}
	
	init(characteristic chr: CBCharacteristic, ofService: Service) {
		cbCharacteristic = chr
		service = ofService
		super.init()
		
		self.load()
	}
	
	func load() {
		if !self.loading {
			self.loading = true
			self.peripheral.cbPeripheral.readValueForCharacteristic(self.cbCharacteristic)
		}
	}
	
	public override var description: String {
		return "\(self.cbCharacteristic)"
	}
	
	public var listenForUpdates: Bool = false {
		didSet {
			if self.propertyEnabled(.Notify) || self.propertyEnabled(.Indicate) {
				println("Setting notification/indications for \(self)")
				self.peripheral.cbPeripheral.setNotifyValue(self.listenForUpdates, forCharacteristic: self.cbCharacteristic)
			}
		}
	}
	
	public func propertyEnabled(prop: CBCharacteristicProperties) -> Bool {
		return (self.cbCharacteristic.properties.rawValue & prop.rawValue) != 0
	}
	
	public func didLoad() {
		self.loading = false
	}
	public var dataValue: NSData? { return self.cbCharacteristic.value }
	public var stringValue: String { if let d = self.dataValue { return (NSString(data: d, encoding: NSASCIIStringEncoding) ?? "") as String; }; return "" }
}
