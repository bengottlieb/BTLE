//
//  BTLECharacteristic.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

public class BTLECharacteristic: NSObject {
	public var cbCharacteristic: CBCharacteristic!
	public var service: BTLEService!
	var loading = false
	
	var peripheral: BTLEPeripheral { return self.service.peripheral }
	
	class func characteristic(chr: CBCharacteristic, ofService: BTLEService?) -> BTLECharacteristic {
	//	if chr.UUID == LockStatusCharacteristic { return BTLELockStatusCharacteristic(characteristic: chr, ofService: ofService) }
		
		return BTLECharacteristic(characteristic: chr, ofService: ofService)
	}
	
	init(characteristic chr: CBCharacteristic, ofService: BTLEService?) {
		cbCharacteristic = chr
		service = ofService
		super.init()
		
		if let svc = ofService { self.load() }
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


public class BTLEMutableCharacteristic : BTLECharacteristic {
	public init(uuid: CBUUID, properties: CBCharacteristicProperties, value: NSData? = nil, permissions: CBAttributePermissions = .Readable) {
		super.init(characteristic: CBMutableCharacteristic(type: uuid, properties: properties, value: value, permissions: permissions), ofService: nil)
	}
}