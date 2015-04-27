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
	public enum ListeningState { case NotListening, StartingToListen, Listening, FinishingListening }
	public var cbCharacteristic: CBCharacteristic!
	public var service: BTLEService!
	public var descriptors: [BTLEDescriptor] = []
	public var listeningState = ListeningState.NotListening { didSet { NSNotification.postNotification(BTLE.notifications.characteristicListeningChanged, object: self) }}
	public override var description: String { return "\(self.cbCharacteristic)" }
	public var publishInProgress = false

	init(characteristic chr: CBCharacteristic, ofService svc: BTLEService?) {
		cbCharacteristic = chr
		service = svc
		
		dataValue = chr.value
		super.init()
		
		if svc != nil { self.reload() }
	}
	
	public func listenForUpdates(listen: Bool) {
		if self.canNotify {
			switch self.listeningState {
			case .NotListening: fallthrough
			case .FinishingListening:
				if listen { self.peripheral.cbPeripheral.setNotifyValue(true, forCharacteristic: self.cbCharacteristic) }
				
			case .Listening: fallthrough
			case .StartingToListen:
				if !listen { self.peripheral.cbPeripheral.setNotifyValue(false, forCharacteristic: self.cbCharacteristic) }
			}
		}
	}
	
	public var canNotify: Bool { return self.propertyEnabled(.Notify) || self.propertyEnabled(.Indicate) }
	public var centralCanWriteTo: Bool { return self.propertyEnabled(.Write) || self.propertyEnabled(.WriteWithoutResponse) }
	public func publishValue(data: NSData, withResponse: Bool = false) {
		if self.centralCanWriteTo {
			self.publishInProgress = true
			self.peripheral.cbPeripheral.writeValue(data, forCharacteristic: self.cbCharacteristic, type: withResponse ? .WithResponse : .WithoutResponse)
		} else {
			println("Trying to write to a read-only characteristic: \(self)")
		}
	}
	
	public func propertyEnabled(prop: CBCharacteristicProperties) -> Bool {
		return (self.cbCharacteristic.properties.rawValue & prop.rawValue) != 0
	}
	
	public func queryDescriptors() {
		self.peripheral.cbPeripheral.discoverDescriptorsForCharacteristic(self.cbCharacteristic)
	}
	
	public var dataValue: NSData?
	public var stringValue: String { if let d = self.dataValue { return (NSString(data: d, encoding: NSASCIIStringEncoding) ?? "") as String; }; return "" }
	
	public var isEncrypted: Bool {
		return self.propertyEnabled(.IndicateEncryptionRequired) || self.propertyEnabled(.NotifyEncryptionRequired) || self.propertyEnabled(.ExtendedProperties)
	}
	
	public var propertiesAsString: String { return BTLECharacteristic.characteristicPropertiesAsString(self.cbCharacteristic.properties) }

	
	//=============================================================================================
	//MARK: Call backs from Peripheral Delegate

	public func didLoadWithError(error: NSError?) {
		if error == nil {
			self.dataValue = self.cbCharacteristic.value
			self.loadingState = .Loaded
		} else {
			self.loadingState = self.loadingState == .Reloading ? .Loaded : .NotLoaded
		}
	}

	public func didWriteValue(error: NSError?) {
		if let error = error {
			println("Error while writing to \(self): \(error)")
		}
		if self.publishInProgress {
			println("publish complete")
			self.publishInProgress = false
		}
	}
	
	func didUpdateNotifyValue() {
		self.listeningState = self.cbCharacteristic.isNotifying ? .Listening : .NotListening
		
	}
	
	public var loadingState = BTLE.LoadingState.NotLoaded
	public func reload() {
		if self.loadingState == .Loaded || self.loadingState == .NotLoaded  {
			self.loadingState = (self.loadingState == .Loaded) ? .Reloading : .Loading
			self.peripheral.cbPeripheral.readValueForCharacteristic(self.cbCharacteristic)
		}
	}
	
	

	var peripheral: BTLEPeripheral { return self.service.peripheral }

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

	//=============================================================================================
	//MARK: Descriptors

	func loadDescriptors() {
		if let descr = self.cbCharacteristic.descriptors as? [CBDescriptor] {
			self.descriptors = descr.map({ return BTLEDescriptor(descriptor: $0)})
		}
	}
	
	func didUpdateValueForDescriptor(descriptor: CBDescriptor) {
		
	}
	
	func didWriteValueForDescriptor(descriptor: CBDescriptor) {
		
	}
	
	
}


public class BTLEMutableCharacteristic : BTLECharacteristic {
	public init(uuid: CBUUID, properties: CBCharacteristicProperties, value: NSData? = nil, permissions: CBAttributePermissions = .Readable) {
		var creationData = properties.rawValue & CBCharacteristicProperties.Notify.rawValue != 0 ? nil : value
		var chr = CBMutableCharacteristic(type: uuid, properties: properties, value: creationData, permissions: permissions)
		super.init(characteristic: chr, ofService: nil)
		self.dataValue = value
	}
	
	public func updateDataValue(data: NSData?) {
		self.dataValue = data
		
		if let data = data {
			let mgr = BTLE.manager.advertiser.cbPeripheralManager!
			if !mgr.updateValue(data, forCharacteristic: self.cbCharacteristic as! CBMutableCharacteristic, onSubscribedCentrals: nil) {
				println("Unable to update \(self)")
			}
		} else {
			println("No data to update \(self)")
		}
	}
}