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
	public var writeBackInProgress = false

	init(characteristic chr: CBCharacteristic, ofService svc: BTLEService?) {
		cbCharacteristic = chr
		service = svc
		
		dataValue = chr.value
		super.init()
		
		BTLE.debugLog(.High, "Characteristic: creating \(self.dynamicType) from \((chr.description as NSString).substringToIndex(50))")
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
	public func writeBackValue(data: NSData, withResponse: Bool = false) -> Bool {
		if self.peripheral.state != .Connected {
			BTLE.debugLog(.Low, "Characteristic: Not currently connected")
			return false
		}
		if self.centralCanWriteTo {
			self.writeBackInProgress = true
			self.peripheral.cbPeripheral.writeValue(data, forCharacteristic: self.cbCharacteristic, type: withResponse ? .WithResponse : .WithoutResponse)
			return true
		} else {
			BTLE.debugLog(.None, "Characteristic: Trying to write to a read-only characteristic: \(self)")
			return false
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
	
	func cancelLoad() {
		switch self.loadingState {
		case .Loading: self.loadingState = .NotLoaded
		case .Reloading: self.loadingState = .Loaded
		default: break
		}
	}

	//=============================================================================================
	//MARK: Call backs from Peripheral Delegate

	public func didLoadWithError(error: NSError?) {
		BTLE.debugLog(.Medium, "Finished reloading \(self.cbCharacteristic.UUID), error: \(error)")

		if error == nil {
			self.dataValue = self.cbCharacteristic.value
			self.loadingState = .Loaded
		} else {
			self.loadingState = self.loadingState == .Reloading ? .Loaded : .NotLoaded
		}
		
		self.sendReloadCompletions(error)
	}

	public func didWriteValue(error: NSError?) {
		if let error = error {
			BTLE.debugLog(.None, "Characteristic: Error while writing to \(self): \(error)")
		}
		if self.writeBackInProgress {
			BTLE.debugLog(.Medium, "Characteristic: writeBack complete")
			self.writeBackInProgress = false
		}
		NSNotification.postNotification(BTLE.notifications.characteristicDidFinishWritingBack, object: self)
	}
	
	func didUpdateNotifyValue() {
		self.listeningState = self.cbCharacteristic.isNotifying ? .Listening : .NotListening
		
	}
	
	var reloadCompletionBlocks: [(NSError?, NSData?) -> Void] = []
	
	func reloadTimedOut(timer: NSTimer) {
		BTLE.debugLog(.Low, "Characteristic: reload timed out")
		self.reloadTimeoutTimer?.invalidate()
		self.sendReloadCompletions(NSError(domain: CBErrorDomain, code: CBError.ConnectionTimeout.rawValue, userInfo: nil))
	}
	
	func sendReloadCompletions(error: NSError?) {
		let completions = self.reloadCompletionBlocks
		self.reloadCompletionBlocks = []
		
		for completion in completions {
			completion(error, self.dataValue)
		}
	}
	
	public var loadingState = BTLE.LoadingState.NotLoaded
	public func reload(timeout: NSTimeInterval = 10.0, completion: ((NSError?, NSData?) -> ())? = nil) {
		BTLE.debugLog(.Medium, "Reloading \(self.cbCharacteristic.UUID)")

		if let completion = completion {
			self.reloadCompletionBlocks.append(completion)
		}

		self.reloadTimeoutTimer?.invalidate()
		if timeout > 0.0 {
			self.reloadTimeoutTimer = NSTimer.scheduledTimerWithTimeInterval(timeout, target: self, selector: "reloadTimedOut:", userInfo: nil, repeats: false)
		}
		
		self.peripheral.connect(completion: { error in
			if self.loadingState == .Loaded || self.loadingState == .NotLoaded  {
				self.loadingState = (self.loadingState == .Loaded) ? .Reloading : .Loading
				let chr = self.cbCharacteristic
				BTLE.debugLog(.High, "Connected, calling readValue on \(self.cbCharacteristic.UUID)")
				self.peripheral.cbPeripheral.readValueForCharacteristic(chr)
			}
		})
	}
	
	weak var reloadTimeoutTimer: NSTimer?

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

	
	public var summaryDescription: String {
		var string = "\(self.cbCharacteristic.UUID): "
		
		switch self.loadingState {
		case .NotLoaded: break
		case .Loading: string = "Loading " + string
		case .Loaded: string = "Loaded " + string
		case .LoadingCancelled: string = "Cancelled " + string
		case .Reloading: string = "Reloading " + string
		}
		
		return string
	}
	
	
	public var fullDescription: String {
		let desc = "\(self.summaryDescription)"
		
		return desc
	}
	

	//=============================================================================================
	//MARK: Descriptors

	func loadDescriptors() {
		if let descr = self.cbCharacteristic.descriptors {
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
		let creationData = properties.rawValue & CBCharacteristicProperties.Notify.rawValue != 0 ? nil : value
		let chr = CBMutableCharacteristic(type: uuid, properties: properties, value: creationData, permissions: permissions)
		super.init(characteristic: chr, ofService: nil)
		self.dataValue = value
	}
	
	public func updateDataValue(data: NSData?) {
		self.dataValue = data
		
		if let data = data {
			let mgr = BTLE.advertiser.cbPeripheralManager!
			if !mgr.updateValue(data, forCharacteristic: self.cbCharacteristic as! CBMutableCharacteristic, onSubscribedCentrals: nil) {
				BTLE.debugLog(.None, "Characteristic: Unable to update \(self)")
			}
		} else {
			BTLE.debugLog(.None, "Characteristic: No data to update \(self)")
		}
	}
}
