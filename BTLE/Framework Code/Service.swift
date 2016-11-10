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

open class BTLEService: NSObject {
	public var cbService: CBService!
	var peripheral: BTLEPeripheral!
	var loadingState = BTLE.LoadingState.notLoaded
	public var characteristics: [BTLECharacteristic] = []
	var pendingCharacteristics: [BTLECharacteristic] = []
	public var uuid: CBUUID { return self.cbService.uuid }
	
	class func createService(service svc: CBService, onPeriperhal: BTLEPeripheral) -> BTLEService {
		if let serviceClass: BTLEService.Type = BTLE.registeredClasses.services[svc.uuid] {
			return serviceClass.init(service: svc, onPeriperhal: onPeriperhal)
		} else {
			return BTLEService(service: svc, onPeriperhal: onPeriperhal)
		}
	}
	
	
	override init() { super.init() }
	
	required public init(service svc: CBService, onPeriperhal: BTLEPeripheral) {
		cbService = svc
		peripheral = onPeriperhal
		super.init()
		
		self.reload()
		BTLE.debugLog(.medium, "Service: creating \(type(of: self)) from \(svc)")
	}
	
	func cancelLoad() {
		switch self.loadingState {
		case .loading: self.loadingState = .notLoaded
		case .reloading: self.loadingState = .loaded
		case .loaded: return
		default: break
		}
		
		for chr in self.characteristics { chr.cancelLoad() }
	}
	
	func reload() {
		if self.loadingState != .loading && self.loadingState != .reloading {
			//println("BTLE Service: Loading Service: \(self), UUID: \(self.uuid)")
			self.loadingState = (self.loadingState == .loaded) ? .reloading : .loading
			
			for chr in self.characteristics {
				chr.reload()
			}
			self.peripheral.cbPeripheral.discoverCharacteristics(nil, for: self.cbService)
		}
	}
	
	func updateCharacteristics() {
		if let characteristics = self.cbService.characteristics {
			for chr in characteristics {
				if self.findCharacteristicMatching(chr: chr) == nil && self.shouldLoadCharacteristic(characteristic: chr) {
					let characteristic = BTLECharacteristic(characteristic: chr, ofService: self)
					self.characteristics.append(characteristic)
				}
			}
		}
	}
	
	public func shouldLoadCharacteristic(characteristic: CBCharacteristic) -> Bool {
		return true
	}
	
	open func didFinishLoading() {
		self.loadingState = .loaded
		self.peripheral.didFinishLoadingService(service: self)
	}
	
	func findCharacteristicMatching(chr: CBCharacteristic) -> BTLECharacteristic? {
		return self.characteristics.filter({ $0.cbCharacteristic == chr }).last
	}
	
	var numberOfLoadingCharacteristics: Int {
		var count = 0
		
		for chr in self.characteristics {
			if chr.loadingState	== .loading || chr.loadingState	== .reloading { count += 1 }
		}
		return count
	}
	
	func didLoadCharacteristic(chr: CBCharacteristic, error: Error?) {
		//println("BTLE Service: Loaded characteristic: \(chr)")
		if let char = self.findCharacteristicMatching(chr: chr) {
			char.didLoadWithError(error: error)
		}
	}
	
	open override var description: String { return "\(self.cbService): \(self.characteristics)" }
	
	public var summaryDescription: String {
		var string = "\(self.cbService.uuid): "

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
		var desc = "\(self.summaryDescription)"
		
		for chr in self.characteristics {
			desc = desc + "\n" + chr.fullDescription
		}
		
		return desc
	}
	

	public func characteristicWithUUID(uuid: CBUUID) -> BTLECharacteristic? { return self.characteristics.filter({ $0.cbCharacteristic.uuid == uuid }).last }
	
}

//=============================================================================================
//MARK: BTLEMutableService


public class BTLEMutableService: BTLEService {
	public var advertised = false
	public var addedToManager = false
	public var isLive = false
	var hasBeenAdded = false
	
	public init(service: CBMutableService, isAdvertised: Bool) {
		super.init()

		self.advertised = isAdvertised
		self.cbService = service
	}

	public init(uuid: CBUUID, isPrimary: Bool = true, characteristics chrs: [BTLECharacteristic] = []) {
		super.init()
		self.cbService = CBMutableService(type: uuid, primary: isPrimary)
		for svc in chrs { self.addCharacteristic(chr: svc) }
	}

	func addToManager(mgr: CBPeripheralManager?) {
		if self.hasBeenAdded {
			return
		}
		if let mgr = mgr, mgr.state == .poweredOn {
			self.hasBeenAdded = true
			mgr.add(self.cbService as! CBMutableService)
		}
	}
	
	func removeFromManager(mgr: CBPeripheralManager?) {
		if let mgr = mgr, mgr.state == .poweredOn {
			if !self.hasBeenAdded { return }
			self.hasBeenAdded = false
			mgr.remove(self.cbService as! CBMutableService)
		}
	}
	

	
	public required init(service svc: CBService, onPeriperhal: BTLEPeripheral) { fatalError("init(service:onPeriperhal:) has not been implemented") }
	
	public func addCharacteristic(chr: BTLECharacteristic) {
		self.characteristics.append(chr)
		chr.service = self
		if let svc = self.cbService as? CBMutableService {
			if svc.characteristics == nil { svc.characteristics = [] }
			svc.characteristics?.append(chr.cbCharacteristic)
		}
	}
	
	
	func replaceCBService(newService: CBMutableService) {
		self.cbService = newService
		self.hasBeenAdded = true
	}

}
