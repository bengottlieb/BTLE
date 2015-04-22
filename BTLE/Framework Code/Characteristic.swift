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
	public var descriptors: [BTLEDescriptor] = []
	
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
	
	public func reload() {
		self.peripheral.cbPeripheral.readValueForCharacteristic(self.cbCharacteristic)
	}
	
	public func publishValue(data: NSData, withResponse: Bool = false) {
		self.peripheral.cbPeripheral.writeValue(data, forCharacteristic: self.cbCharacteristic, type: withResponse ? .WithResponse : .WithoutResponse)
	}
	
	public func propertyEnabled(prop: CBCharacteristicProperties) -> Bool {
		return (self.cbCharacteristic.properties.rawValue & prop.rawValue) != 0
	}
	
	public func queryDescriptors() {
		self.peripheral.cbPeripheral.discoverDescriptorsForCharacteristic(self.cbCharacteristic)
	}
	
	public func didLoad() {
		self.dataValue = self.cbCharacteristic.value
		self.loading = false
	}
	public var dataValue: NSData?
	public var stringValue: String { if let d = self.dataValue { return (NSString(data: d, encoding: NSASCIIStringEncoding) ?? "") as String; }; return "" }
	public var isEncrypted: Bool {
		return self.cbCharacteristic.properties.rawValue & (CBCharacteristicProperties.IndicateEncryptionRequired.rawValue | CBCharacteristicProperties.NotifyEncryptionRequired.rawValue | CBCharacteristicProperties.ExtendedProperties.rawValue) != 0
	}
	
	public var propertiesAsString: String { return BTLECharacteristic.characteristicPropertiesAsString(self.cbCharacteristic.properties) }

	
	func didWriteValue() {
		
	}
	
	func didUpdateValueForDescriptor(descriptor: CBDescriptor) {
		
	}
	
	func didWriteValueForDescriptor(descriptor: CBDescriptor) {
		
	}
	
	func didUpdateNotifyValue() {
		
	}
	
	func loadDescriptors() {
		if let descr = self.cbCharacteristic.descriptors as? [CBDescriptor] {
			self.descriptors = descr.map({ return BTLEDescriptor(descriptor: $0)})
		}
	}
	
	var loading = false
	
	var peripheral: BTLEPeripheral { return self.service.peripheral }
	
	init(characteristic chr: CBCharacteristic, ofService svc: BTLEService?) {
		cbCharacteristic = chr
		service = svc
		
		dataValue = chr.value
		super.init()
		
		if svc != nil { self.load() }
	}
	
	func load() {
		if !self.loading {
			self.loading = true
			self.peripheral.cbPeripheral.readValueForCharacteristic(self.cbCharacteristic)
		}
	}
	

	class func characteristicPropertiesAsString(chr: CBCharacteristicProperties) -> String {
		var string = ""
	
		if chr.rawValue & CBCharacteristicProperties.Broadcast.rawValue > 0 { string += "Broadcast, " }
		if chr.rawValue & CBCharacteristicProperties.Read.rawValue > 0 { string += "Read, " }
		if chr.rawValue & CBCharacteristicProperties.WriteWithoutResponse.rawValue > 0 { string += "WriteWithoutResponse, " }
		if chr.rawValue & CBCharacteristicProperties.Write.rawValue > 0 { string += "Write, " }
		if chr.rawValue & CBCharacteristicProperties.Notify.rawValue > 0 { string += "Notify, " }
		if chr.rawValue & CBCharacteristicProperties.Indicate.rawValue > 0 { string += "Indicate, " }
		if chr.rawValue & CBCharacteristicProperties.AuthenticatedSignedWrites.rawValue > 0 { string += "AuthenticatedSignedWrites, " }
		if chr.rawValue & CBCharacteristicProperties.ExtendedProperties.rawValue > 0 { string += "ExtendedProperties, " }
		if chr.rawValue & CBCharacteristicProperties.NotifyEncryptionRequired.rawValue > 0 { string += "NotifyEncryptionRequired, " }
		if chr.rawValue & CBCharacteristicProperties.IndicateEncryptionRequired.rawValue > 0 { string += "IndicateEncryptionRequired, " }
		
		return string
	}
}


public class BTLEMutableCharacteristic : BTLECharacteristic {
	public init(uuid: CBUUID, properties: CBCharacteristicProperties, value: NSData? = nil, permissions: CBAttributePermissions = .Readable) {
		super.init(characteristic: CBMutableCharacteristic(type: uuid, properties: properties, value: value, permissions: permissions), ofService: nil)
	}
	
	public func updateDataValue(data: NSData?) {
		self.dataValue = data
		
		if let data = data {
			let mgr = BTLE.manager.advertiser.cbPeripheralManager!
			mgr.updateValue(data, forCharacteristic: self.cbCharacteristic as! CBMutableCharacteristic, onSubscribedCentrals: nil)
		}
	}
}