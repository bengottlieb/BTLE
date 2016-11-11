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
	public enum State { case notListening, startingToListen, listening, finishingListening, updated }
	public var cbCharacteristic: CBCharacteristic!
	public var service: BTLEService!
	public var descriptors: [BTLEDescriptor] = []
	public var state = State.notListening { didSet { Notification.postOnMainThread(name: BTLE.notifications.characteristicListeningChanged, object: self) }}
	public override var description: String { return "\(self.cbCharacteristic)" }
	public var writeBackInProgress: Bool { return self.writeBackCompletion != nil }
	public private(set) var reloadInProgress: Bool = false

	init(characteristic chr: CBCharacteristic, ofService svc: BTLEService?) {
		cbCharacteristic = chr
		service = svc
		
		dataValue = chr.value as NSData?
		super.init()
		
		BTLE.debugLog(.high, "Characteristic: creating \(type(of: self)) from \((chr.description as NSString).substring(to: 50))")
		if svc != nil { self.reload() }
	}
	
	public func stopListeningForUpdates() {
		if self.canNotify && (self.state == .listening || self.state == .startingToListen) {
			if self.cbCharacteristic.isNotifying {
				self.state = .finishingListening
				self.peripheral.cbPeripheral.setNotifyValue(false, for: self.cbCharacteristic)
			} else {
				self.state = .notListening
			}
			self.updateListeners(newState: .finishingListening)
		}
		self.updateClosures = []
	}
	
	var updateClosures: [(State, BTLECharacteristic) -> Void] = []
	public func listenForUpdates(closure: @escaping (State, BTLECharacteristic) -> Void) {
		if self.canNotify && (self.state == .notListening || self.state == .finishingListening) {
			self.state = .startingToListen
			self.peripheral.cbPeripheral.setNotifyValue(true, for: self.cbCharacteristic)
		}
		self.updateClosures.append(closure)
	}
	
	public var canNotify: Bool { return self.propertyEnabled(prop: .notify) || self.propertyEnabled(prop: .indicate) }
	public var centralCanWriteTo: Bool { return self.propertyEnabled(prop: .write) || self.propertyEnabled(prop: .writeWithoutResponse) }
	
	var writeBackCompletion: ((BTLECharacteristic, Error?) -> Void)?
	@discardableResult public func writeBackValue(data: NSData, completion: ((BTLECharacteristic, Error?) -> Void)? = nil) -> Bool {
		if self.peripheral.state != .connected {
			completion?(self, NSError(type: .characteristicNotConnected))
			return false
		}
		if self.writeBackCompletion != nil {
			completion?(self, NSError(type: .characteristicHasPendingWriteInProgress))
			return false
		}
		if self.centralCanWriteTo {
			self.writeBackCompletion = completion
			self.peripheral.cbPeripheral.writeValue(data as Data, for: self.cbCharacteristic, type: completion != nil ? .withResponse : .withoutResponse)
			return true
		} else {
			BTLE.debugLog(.none, "Characteristic: Trying to write to a read-only characteristic: \(self)")
			completion?(self, NSError(type: .characteristicNotWritable))
			return false
		}
	}
	
	func updateListeners(newState: State) {
		self.updateClosures.forEach { $0(newState, self) }
	}
	
	public func propertyEnabled(prop: CBCharacteristicProperties) -> Bool {
		return (self.cbCharacteristic.properties.rawValue & prop.rawValue) != 0
	}
	
	public func queryDescriptors() {
		self.peripheral.cbPeripheral.discoverDescriptors(for: self.cbCharacteristic)
	}
	
	public var dataValue: NSData?
	public var stringValue: String { if let d = self.dataValue { return (String(data: d as Data, encoding: .ascii) ?? "") }; return "" }
	
	public var isEncrypted: Bool {
		return self.propertyEnabled(prop: .indicateEncryptionRequired) || self.propertyEnabled(prop: .notifyEncryptionRequired) || self.propertyEnabled(prop: .extendedProperties)
	}
	
	public var propertiesAsString: String { return BTLECharacteristic.characteristicPropertiesAsString(chr: self.cbCharacteristic.properties) }
	
	func cancelLoad() {
		BTLE.debugLog(.medium, "Canceling load on \(self.cbCharacteristic)")
		switch self.loadingState {
		case .loading: self.loadingState = .notLoaded
		case .reloading: self.loadingState = .loaded
		default: break
		}
	}

	//=============================================================================================
	//MARK: Call backs from Peripheral Delegate
	
	public func didLoad(with error: Error?) {
		BTLE.debugLog(.medium, "Finished reloading \(self.cbCharacteristic.uuid), error: \(error)")

		if error == nil {
			self.dataValue = self.cbCharacteristic.value as NSData?
			self.loadingState = .loaded
		} else {
			self.loadingState = self.loadingState == .reloading ? .loaded : .notLoaded
		}
		
		if self.service.numberOfLoadingCharacteristics == 0 {
			self.service.didFinishLoading()
		}
		self.updateListeners(newState: .updated)
		Notification.postOnMainThread(name: BTLE.notifications.characteristicDidUpdate, object: self, userInfo: nil)

		self.sendReloadCompletions(error: error)
	}

	public func didWriteValue(error: Error?) {
		if let error = error {
			BTLE.debugLog(.none, "Characteristic: Error while writing to \(self): \(error)")
		}
		self.writeBackCompletion?(self, error)
		self.writeBackCompletion = nil

		Notification.postOnMainThread(name: BTLE.notifications.characteristicDidFinishWritingBack, object: self)
	}
	
	func didUpdateNotifyValue() {
		self.state = self.cbCharacteristic.isNotifying ? .listening : .notListening
		self.updateListeners(newState: self.state)
		
	}
	
	var reloadCompletionBlocks: [(Error?, NSData?) -> Void] = []
	
	func reloadTimedOut(timer: Timer) {
		BTLE.debugLog(.low, "Characteristic: reload timed out")
		self.reloadTimeoutTimer?.invalidate()
		self.sendReloadCompletions(error: NSError(domain: CBErrorDomain, code: CBError.connectionTimeout.rawValue, userInfo: nil))
		self.reloadInProgress = false
	}
	
	func sendReloadCompletions(error: Error?) {
		let completions = self.reloadCompletionBlocks
		self.reloadCompletionBlocks = []
		
		for completion in completions {
			completion(error, self.dataValue)
		}
	}
	
	public var loadingState = BTLE.LoadingState.notLoaded
	public func reload(timeout: TimeInterval = 10.0, completion: ((Error?, NSData?) -> ())? = nil) {
		if !self.propertyEnabled(prop: .read) {
			let error = NSError(domain: CBErrorDomain, code: CBError.invalidParameters.rawValue, userInfo: nil)
			self.didLoad(with: error)
			completion?(error, nil)
			return
		}
		
		self.reloadInProgress = true
		BTLE.debugLog(.medium, "Reloading \(self.cbCharacteristic.uuid)")

		if let completion = completion {
			self.reloadCompletionBlocks.append(completion)
		}

		self.reloadTimeoutTimer?.invalidate()
		btle_dispatch_main {
			self.reloadTimeoutTimer = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(BTLECharacteristic.reloadTimedOut), userInfo: nil, repeats: false)
		}
		
		self.peripheral.connect(completion: { error in
			if self.loadingState == .loaded || self.loadingState == .notLoaded  {
				self.loadingState = (self.loadingState == .loaded) ? .reloading : .loading
				let chr = self.cbCharacteristic
				BTLE.debugLog(.high, "Connected, calling readValue on \(self.cbCharacteristic.uuid)")
				self.peripheral.cbPeripheral.readValue(for: chr!)
				self.reloadInProgress = false
			}
		})
	}
	
	weak var reloadTimeoutTimer: Timer?

	var peripheral: BTLEPeripheral { return self.service.peripheral }

	class func characteristicPropertiesAsString(chr: CBCharacteristicProperties) -> String {
		var string = ""
	
		if chr.rawValue & CBCharacteristicProperties.broadcast.rawValue > 0 { string += "Broadcast, " }
		if chr.rawValue & CBCharacteristicProperties.read.rawValue > 0 { string += "Read, " }
		if chr.rawValue & CBCharacteristicProperties.writeWithoutResponse.rawValue > 0 { string += "WriteWithoutResponse, " }
		if chr.rawValue & CBCharacteristicProperties.write.rawValue > 0 { string += "Write, " }
		if chr.rawValue & CBCharacteristicProperties.notify.rawValue > 0 { string += "Notify, " }
		if chr.rawValue & CBCharacteristicProperties.indicate.rawValue > 0 { string += "Indicate, " }
		if chr.rawValue & CBCharacteristicProperties.authenticatedSignedWrites.rawValue > 0 { string += "AuthenticatedSignedWrites, " }
		if chr.rawValue & CBCharacteristicProperties.extendedProperties.rawValue > 0 { string += "ExtendedProperties, " }
		if chr.rawValue & CBCharacteristicProperties.notifyEncryptionRequired.rawValue > 0 { string += "NotifyEncryptionRequired, " }
		if chr.rawValue & CBCharacteristicProperties.indicateEncryptionRequired.rawValue > 0 { string += "IndicateEncryptionRequired, " }
		
		return string
	}

	
	public var summaryDescription: String {
		var string = "\(self.cbCharacteristic.uuid): "
		
		switch self.loadingState {
		case .notLoaded: break
		case .loading: string = "Loading " + string
		case .loaded: string = "Loaded " + string
		case .loadingCancelled: string = "Cancelled " + string
		case .reloading: string = "Reloading " + string
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
	public init(uuid: CBUUID, properties: CBCharacteristicProperties = [.read], value: NSData? = nil, permissions: CBAttributePermissions = .readable) {
		let creationData = properties.rawValue & CBCharacteristicProperties.notify.rawValue != 0 ? nil : value
		let chr = CBMutableCharacteristic(type: uuid, properties: properties, value: creationData as Data?, permissions: permissions)
		super.init(characteristic: chr, ofService: nil)
		self.dataValue = value
	}
	
	public func updateDataValue(data: NSData?) {
		self.dataValue = data
		
		if let data = data {
			let mgr = BTLE.advertiser.cbPeripheralManager!
			if !mgr.updateValue(data as Data, for: self.cbCharacteristic as! CBMutableCharacteristic, onSubscribedCentrals: nil) {
				BTLE.debugLog(.none, "Characteristic: Unable to update \(self)")
			}
		} else {
			BTLE.debugLog(.none, "Characteristic: No data to update \(self)")
		}
	}
}
