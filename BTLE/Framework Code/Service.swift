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

public class BTLEService: NSObject, Printable {
	public var cbService: CBService!
	var peripheral: BTLEPeripheral!
	var loadingState = BTLE.LoadingState.NotLoaded
	public var characteristics: [BTLECharacteristic] = []
	var pendingCharacteristics: [BTLECharacteristic] = []
	public var uuid: CBUUID { return self.cbService.UUID }
	
	class func createService(service svc: CBService, onPeriperhal: BTLEPeripheral) -> BTLEService {
		if let serviceClass: BTLEService.Type = BTLE.registeredClasses.services[svc.UUID] {
			return serviceClass(service: svc, onPeriperhal: onPeriperhal)
		} else {
			return BTLEService(service: svc, onPeriperhal: onPeriperhal)
		}
	}
	
	
	override init() { super.init() }
	
	required public init(service svc: CBService, onPeriperhal: BTLEPeripheral) {
		if BTLE.debugLevel == .High { println("creating service from \(svc)") }
		cbService = svc
		peripheral = onPeriperhal
		super.init()
		
		self.reload()
	}
	
	func cancelLoad() {
		switch self.loadingState {
		case .Loading: self.loadingState = .NotLoaded
		case .Reloading: self.loadingState = .Loaded
		default: break
		}
		
		for chr in self.characteristics { chr.cancelLoad() }
	}
	
	func reload() {
		if self.loadingState != .Loading && self.loadingState != .Reloading {
			//println("Loading Service: \(self), UUID: \(self.uuid)")
			self.loadingState = (self.loadingState == .Loaded) ? .Reloading : .Loading
			
			for chr in self.characteristics {
				chr.reload()
			}
			self.peripheral.cbPeripheral.discoverCharacteristics(nil, forService: self.cbService)
		}
	}
	
	func updateCharacteristics() {
		if let characteristics = self.cbService.characteristics as? [CBCharacteristic] {
			for chr in characteristics {
				if self.findCharacteristicMatching(chr) == nil && self.shouldLoadCharacteristic(chr) {
					var characteristic = BTLECharacteristic(characteristic: chr, ofService: self)
					self.characteristics.append(characteristic)
				}
			}
		}
	}
	
	public func shouldLoadCharacteristic(characteristic: CBCharacteristic) -> Bool {
		return true
	}
	
	public func didFinishLoading() {
		self.loadingState = .Loaded
		self.peripheral.didFinishLoadingService(self)
	}
	
	func findCharacteristicMatching(chr: CBCharacteristic) -> BTLECharacteristic? {
		return filter(self.characteristics, { $0.cbCharacteristic == chr }).last
	}
	
	var numberOfLoadingCharacteristics: Int {
		var count = 0
		
		for chr in self.characteristics {
			if chr.loadingState	== .Loading || chr.loadingState	== .Reloading { count++ }
		}
		return count
	}
	
	func didLoadCharacteristic(chr: CBCharacteristic, error: NSError?) {
		//println("Loaded characteristic: \(chr)")
		if let char = self.findCharacteristicMatching(chr) {
			char.didLoadWithError(error)
			if self.numberOfLoadingCharacteristics == 0 {
				self.didFinishLoading()
			}
			NSNotification.postNotification(BTLE.notifications.characteristicDidUpdate, object: char, userInfo: nil)
		}
	}
	
	public override var description: String { return "\(self.cbService): \(self.characteristics)" }
	
	public var summaryDescription: String {
		var string = "\(self.cbService.UUID): "

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
		var desc = "\(self.summaryDescription)"
		
		for chr in self.characteristics {
			desc = desc + "\n" + chr.fullDescription
		}
		
		return desc
	}
	

	public func characteristicWithUUID(uuid: CBUUID) -> BTLECharacteristic? { return filter(self.characteristics, { $0.cbCharacteristic.UUID == uuid }).last }

	func addToPeripheralManager(mgr: CBPeripheralManager?) { }
	
}

//=============================================================================================
//MARK: BTLEMutableService


public class BTLEMutableService: BTLEService {
	public var advertised = false
	public var addedToManager = false
	public var isLive = false
	

	public init(uuid: CBUUID, isPrimary: Bool = true, characteristics chrs: [BTLECharacteristic] = []) {
		if BTLE.debugLevel == .High { println("creating mutable peripheral from") }
		super.init()
		self.cbService = CBMutableService(type: uuid, primary: isPrimary)
		for svc in chrs { self.addCharacteristic(svc) }
	}

	public required init(service svc: CBService, onPeriperhal: BTLEPeripheral) { fatalError("init(service:onPeriperhal:) has not been implemented") }
	
	public func addCharacteristic(chr: BTLECharacteristic) {
		self.characteristics.append(chr)
		chr.service = self
		if let svc = self.cbService as? CBMutableService {
			if svc.characteristics == nil { svc.characteristics = [] }
			svc.characteristics.append(chr.cbCharacteristic)
		}
	}
	
	override func addToPeripheralManager(mgr: CBPeripheralManager?) {
		if self.addedToManager { return }
		if let mgr = mgr {
			if let mutable = self.cbService as? CBMutableService {
				mgr.addService(mutable)
				self.addedToManager = true
			}
		}
	}
	

}