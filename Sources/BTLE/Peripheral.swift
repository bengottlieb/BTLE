//
//  BTLEPeripheral.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth
import Combine
import Suite

let rssi_range_touching = -25
let rssi_range_very_close = -30
let rssi_range_close = -35
let rssi_range_nearby = -45
let rssi_range_same_room = -55
let rssi_range_around = -65


protocol BTLEPeripheralProtocol {
	init();
	init(peripheral: CBPeripheral, RSSI: BTLEPeripheral.RSSValue?, advertisementData adv: [String: Any]?);
}

open class BTLEPeripheral: NSObject, ObservableObject, CBPeripheralDelegate {
	deinit {
		self.rssiTimer?.invalidate()
		self.connectionTimeoutTimer?.invalidate()
		BTLEManager.debugLog(.superHigh, "BTLE Peripheral: deiniting: \(self)")
	}
	
	public enum PeripheralError: LocalizedError { case serviceNotFound, characteristicNotFound, noCharacteristicData
		public var errorDescription: String? {
			switch self {
			case .serviceNotFound: return "Service not found"
			case .characteristicNotFound: return "Characteristic not found"
			case .noCharacteristicData: return "Characteristic returned no data"
			}
		}
	}
	
	public static var unknownDeviceName = "Unknown Name"
	public var cbPeripheral: CBPeripheral!
	public var uuid: UUID!
	public var name: String?
	public var pertinentServices: [CBUUID]?
	public var sendCompletionsWhenFullyLoaded = true
	public var lastCommunicatedAt = Date() { didSet {
		if self.state == .undiscovered {
			self.state = .discovered
			self.sendNotification(name: BTLEManager.Notifications.peripheralDidRegainComms)
		}
		btle_delay(0.001) { self.updateVisibilityTimer() }
	}}
	public var loadingState = BTLEManager.LoadingState.notLoaded {
		didSet {
			if self.loadingState == .loaded {
				self.sendNotification(name: BTLEManager.Notifications.peripheralDidFinishLoading)
				BTLEManager.debugLog(.medium, "BTLE Peripheral: Loaded: \(self.fullDescription)")
				self.sendConnectionCompletions(error: nil)
			}
		}
	}
	public var services: [BTLEService] = []
	public var advertisementData: [String: Any] = [:] { didSet {
		if self.advertisementData != oldValue {
			self.sendNotification(name: BTLEManager.Notifications.peripheralDidUpdateAdvertisementData)
		}
	}}
    public var visibleName: String {
        name ?? iPhoneModelName ?? Self.unknownDeviceName
    }
    
    public var iPhoneModelName: String? {
        guard let service = self.service(with: .deviceInfo) else { return nil }
        
        return service.iPhoneModelName
    }
	
	public var state: State = .discovered { didSet {
		if self.state == oldValue { return }
	
		BTLEManager.debugLog(.medium, "Changing state on \(self.visibleName), \(oldValue.description) -> \(self.state.description)")
	
		switch self.state {
		case .connected:
			self.updateRSSI()
			if self.loadingState == .notLoaded { self.reloadServices() }
			
			
		case .disconnecting: fallthrough
		case .discovered:
			self.cancelLoad()
			
		case .undiscovered:
			self.disconnect()
			
		default: break
		}
		self.objectWillChange.sendOnMain()
	}}
	
	public var rssiUpdateInterval: TimeInterval? { didSet {
		if self.rssiUpdateInterval == nil {
			self.rssiTimer?.invalidate()
		} else {
			self.updateRSSI()
		}
		
	}}
	public var rssi: RSSValue? { didSet {
		self.lastCommunicatedAt = Date()
		self.sendNotification(name: BTLEManager.Notifications.peripheralDidUpdateRSSI)
	}}
	public var rawRSSI: RSSValue?
	
	public var distance: Distance { if let rssi = self.rssi { return Distance(raw: rssi) }; return .unknown }
	
	public var rssiHistory: [(Date, RSSValue)] = []
	
	open override var description: String {
		return "Peripheral: \(self.visibleName) (\(self.uuid.uuidString)), \(self.state), \(self.rssi ?? -1)"
	}

	func didFailToConnect(error: Error?) {
		BTLEManager.debugLog(.medium, "Failed to connect \(self.visibleName): \(error?.localizedDescription ?? "")")
		self.sendConnectionCompletions(error: error)
	}
	
	func sendConnectionCompletions(error: Error?) {
		if self.sendCompletionsWhenFullyLoaded && (self.loadingState == .loading || self.loadingState == .reloading) { return }
		
		self.connectionTimeoutTimer?.invalidate()
		BTLEManager.debugLog(.medium, "Sending \(self.connectionCompletionBlocks.count) completion messages (\(error?.localizedDescription ?? ""))")
		let completions = self.connectionCompletionBlocks
		self.connectionCompletionBlocks = []
		
		for block in completions {
			block(error)
		}
	}
	
	func setCurrentRSSI(newRSSI: RSSValue) {
		if abs(newRSSI) == 127 { return }
		
		if state == .undiscovered { state = .discovered }
		self.rawRSSI = newRSSI
		if BTLEManager.instance.disableRSSISmoothing {
			self.rssi = newRSSI
		} else {
			self.rssiHistory.append((Date(), newRSSI))
			if self.rssiHistory.count > BTLEManager.instance.rssiSmoothingHistoryDepth { self.rssiHistory.remove(at: 0) }
			
			self.rssi = self.rssiHistory.reduce(0, { $0 + $1.1 }) / self.rssiHistory.count
		}
		self.lastCommunicatedAt = Date()
		self.objectWillChange.sendOnMain()
	}
	
	public override required init() {
		super.init()
	}
	
	public required init(peripheral: CBPeripheral, RSSI: RSSValue?, advertisementData adv: [String: Any]?) {
		BTLEManager.debugLog(.high, "Peripheral: creating from \(peripheral)")
		
		cbPeripheral = peripheral
		uuid = peripheral.identifier
        name = peripheral.name
		if let adv = adv {
			advertisementData = adv
		}
		
		super.init()

		peripheral.delegate = self
		self.rssi = RSSI
		self.updateVisibilityTimer()

		if BTLEManager.scanner.ignoredPeripheralUUIDs.contains(peripheral.identifier.uuidString) {
			ignored = .blackList
			BTLEManager.debugLog(.medium, "Peripheral: Ignoring: \(visibleName), \(uuid?.uuidString ?? "")")
		} else if BTLEManager.instance.serviceIDsToScanFor.count > 0 {
			if BTLEManager.instance.serviceFilter == .advertisingData {
				if let info = adv {
					self.updateIgnoredWithAdvertisingData(info: info)
				} else {
					self.ignored = .missingServices
				}
			} else if BTLEManager.instance.serviceFilter == .actualServices {
				self.ignored = .checkingForServices
				_ = self.connect(services: self.pertinentServices)
			}
		}
		
		if self.ignored == .not {
			BTLEManager.debugLog(.medium, "BTLE Peripheral: not ignored: \(self)")
		}
	}
	
	func updateIgnoredWithAdvertisingData(info: [String: Any]) {
		BTLEManager.scanner.dispatchQueue.async {
			if BTLEManager.instance.serviceFilter == .advertisingData && BTLEManager.instance.serviceIDsToScanFor.count > 0 {
				var ignored = true
				if let services = info[CBAdvertisementDataServiceUUIDsKey] as? NSArray {
					for service in services {
						if let cbid = service as? CBUUID {
							if BTLEManager.instance.serviceIDsToScanFor.contains(cbid) { ignored = false; break }
						}
					}
				}
				if ignored {
					self.ignored = .missingServices
					BTLEManager.debugLog(.superHigh, "BTLE Peripheral: ignored \(self.cbPeripheral.name ?? "") with advertising info: \(info)")
				} else {
					self.ignored = .not
				}
			}
		}
	}
	
	public func ignore(ignore: Ignored = .blackList) {
		self.ignored = ignore
	}
	
	var connectionCompletionBlocks: [(Error?) -> Void] = []
	weak var connectionTimeoutTimer: Timer?
	 
	@objc public func connectionTimedOut() {
		self.state = .discovered
		self.sendConnectionCompletions(error: NSError(type: .peripheralConnectionTimedOut))
	}
	
	public func connect(reloadServices: Bool = false, services: [CBUUID]? = nil, timeout: TimeInterval? = nil, completion: ((Error?) -> ())? = nil) {
		BTLEManager.scanner.dispatchQueue.async {
			BTLEManager.debugLog(.high, "Peripheral: connecting for \(services?.description ?? "all services")")
			self.pertinentServices = services

			if let completion = completion { self.connectionCompletionBlocks.append(completion) }
			switch self.state {
			case .connecting:
				break
				
			case .connected:
				self.sendConnectionCompletions(error: nil)
				
			case .discovered: fallthrough
			case .disconnecting: fallthrough
			case .undiscovered: fallthrough
			case .unknown:
				if let timeout = timeout {
					DispatchQueue.main.async {
						self.connectionTimeoutTimer = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(
							self.connectionTimedOut), userInfo: nil, repeats: false)
					}
				}
				if (reloadServices) { self.loadingState = .reloading }
				BTLEManager.debugLog(.medium, "Attempting to connect to \(self.visibleName), current state: \(self.state.description)")
				self.state = .connecting
				BTLEManager.scanner.cbCentral.connect(self.cbPeripheral, options: [:])
			}
		}
	}
		
	public func disconnect() {
		BTLEManager.debugLog(.medium, "Disconnecting from \(self.visibleName), current state: \(self.state.description)")
		if self.state == .connected { self.state = .disconnecting }
		
		BTLEManager.scanner.cbCentral?.cancelPeripheralConnection(self.cbPeripheral)
	}
	
	func cancelLoad() {
		BTLEManager.scanner.dispatchQueue.async {
			if self.loadingState == .loading {
				BTLEManager.debugLog(.medium, "Aborting service load on \(self.visibleName)")
				self.loadingState = .loadingCancelled
			}
			
			for svc in self.services { svc.cancelLoad() }
		}
	}
	
	public var ignored: Ignored = .not {
		didSet {
			if oldValue != self.ignored {
				if self.ignored == .blackList {
					BTLEManager.scanner.addIgnored(peripheral: self)
				} else if self.ignored == .not {
					BTLEManager.scanner.removeIgnored(peripheral: self)
				}
			}
			
		}
	}
	
	public var summaryDescription: String {
		var string = ""
		if self.state == .connected { string = "Connected " + string }
		if self.state == .connecting { string = "Connecting " + string }
		
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
		var desc = "\(self.summaryDescription)\n\(self.advertisementData)"
		
		for svc in self.services {
			desc = desc + "\n" + svc.fullDescription
		}
		
		return desc
	}
	
	@objc public func updateRSSI() {
		self.rssiTimer?.invalidate()
		self.cbPeripheral.readRSSI()
	}
	
	public func service(with uuid: CBUUID?) -> BTLEService? { return self.services.filter({ $0.cbService.uuid == uuid }).last }
	public func characteristic(with uuid: CBUUID) -> BTLECharacteristic? {
		for service in self.services {
			if let chr = service.characteristic(with: uuid) { return chr }
		}
		return nil
	}
	public func characteristicFromCBCharacteristic(characteristic: CBCharacteristic?) -> BTLECharacteristic? {
		guard let characteristic = characteristic else { return nil }
		
		if let service = self.service(with: characteristic.service?.uuid) {
			if let chr = service.characteristic(with: characteristic.uuid) {
				return chr
			}
		}
		BTLEManager.debugLog(.high, "Unabled to find characteristic \(characteristic) \(self.visibleName), current state: \(self.state.description)")
		return nil
	}
	
	public func reloadServices(completely: Bool = false) {
		BTLEManager.scanner.dispatchQueue.async {
			BTLEManager.debugLog(.high, "Loading services on \(self.visibleName)")
			if completely { self.services = [] }
			if self.ignored == .checkingForServices {
				self.cbPeripheral.discoverServices(self.pertinentServices)
			} else {
				self.cbPeripheral.discoverServices(self.pertinentServices)
			}
		}
	}
	
	//=============================================================================================
	//MARK: Internal
	func loadServices(services: [BTLEService]? = nil) {
		var loadThese = services
		
		if loadThese == nil {
			loadThese = self.services.filter { self.pertinentServices == nil ? true : self.pertinentServices!.contains($0.uuid) }
		}
		self.sendNotification(name: BTLEManager.Notifications.peripheralDidBeginLoading)
		self.loadingState = .loading
		for service in loadThese! {
			service.reload()
		}
	}
	
	func didFinishLoadingService(service: BTLEService) {
		BTLEManager.scanner.dispatchQueue.async {
			BTLEManager.debugLog(.medium, "BTLE Peripheral: Finished loading \(service.uuid), \(self.numberOfLoadingServices) left")
			if self.numberOfLoadingServices == 0 {
				self.loadingState = .loaded
			}
		}
	}
	
	var numberOfLoadingServices: Int {
		var count = 0
		
		for chr in self.services {
			if chr.loadingState == .loading || chr.loadingState == .reloading { count += 1 }
		}
		return count
	}

	@discardableResult func findOrCreateService(cbService: CBService?) -> BTLEService? {
		guard let cbService = cbService, self.shouldLoadService(service: cbService) else { return nil }
		
		if let service = self.service(with: cbService.uuid) {
			return service
		}
		
		let service = BTLEService.create(service: cbService, onPeriperhal: self)
		self.services.append(service)

		return service
	}
	
	//=============================================================================================
	//MARK: Timeout

	weak var visibilityTimer: Timer?
	@discardableResult func updateVisibilityTimer() -> Timer? {
		self.visibilityTimer?.invalidate()
		self.visibilityTimer = nil
		
		if self.state == .discovered && BTLEManager.instance.deviceLifetime > 0 {
			btle_dispatch_main { [weak self] in
				if let me = self {
					let timeSinceLastComms = abs(me.lastCommunicatedAt.timeIntervalSinceNow)
					if BTLEManager.instance.deviceLifetime > timeSinceLastComms {
						let timeoutInverval = (BTLEManager.instance.deviceLifetime - timeSinceLastComms)
						
						// if timeoutInverval < 3 { println("BTLE Peripheral: short term timer: \(timeSinceLastComms) sec") }
						
						me.visibilityTimer?.invalidate()
						DispatchQueue.main.async {
							me.visibilityTimer = Timer.scheduledTimer(timeInterval: timeoutInverval, target: me, selector: #selector(BTLEPeripheral.disconnectDueToTimeout), userInfo: nil, repeats: false)
						}
					} else if BTLEManager.instance.deviceLifetime > 0 {
						me.disconnectDueToTimeout()
					}
				}
			}
			
		}
		
		return nil
	}
	
	@objc func disconnectDueToTimeout() {
		BTLEManager.scanner.dispatchQueue.async {
			self.visibilityTimer?.invalidate()
			self.visibilityTimer = nil
			
			if self.state == .discovered {
				self.state = .undiscovered
				self.sendNotification(name: BTLEManager.Notifications.peripheralDidLoseComms)
			}
		}
	}
	
	func sendNotification(name: Notification.Name) {
		if self.ignored != .blackList { Notification.postOnMainThread(name: name, object: self) }
	}

	//=============================================================================================
	//MARK: Delegate - Peripheral
	
	weak var rssiTimer: Timer?
	public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		self.rssi = RSSI.intValue
		self.objectWillChange.sendOnMain()
		if let interval = self.rssiUpdateInterval {
			DispatchQueue.main.async {
				self.rssiTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(self.updateRSSI), userInfo: nil, repeats: false)
			}
		}
	}

	public func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
		BTLEManager.scanner.dispatchQueue.async {
			self.name = peripheral.name
			self.sendNotification(name: BTLEManager.Notifications.peripheralDidUpdateName)
			BTLEManager.debugLog(.medium, "Peripheral: Updated name for: \(self.visibleName)")
		}
	}

	//=============================================================================================
	//MARK: Delegate - Service
	public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
		BTLEManager.scanner.dispatchQueue.async {
			for invalidated in invalidatedServices {
				if self.shouldLoadService(service: invalidated) {
					self.findOrCreateService(cbService: invalidated)?.reload()
				}
			}
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		BTLEManager.scanner.dispatchQueue.async {
			BTLEManager.debugLog(.medium, "Discovered \(self.cbPeripheral.services?.count ?? 0) on \(self.visibleName)")
			
			if let services = self.cbPeripheral.services {
				if self.ignored == .checkingForServices {
					for svc in services {
						BTLEManager.debugLog(.medium, "\(self.visibleName) loading \(svc.uuid)")
						if BTLEManager.instance.serviceIDsToScanFor.contains(svc.uuid) {
							self.ignored = .not
							BTLEManager.scanner.pendingPeripheralFinishLoadingServices(peripheral: self)
							break
						}
					}
				}
				for svc in services {
					if self.shouldLoadService(service: svc) {
						self.findOrCreateService(cbService: svc)
					}
				}
				
				if self.numberOfLoadingServices == 0 {
					self.loadingState = .loaded
					if self.ignored == .checkingForServices {
						self.ignored = .missingServices
						BTLEManager.scanner.pendingPeripheralFinishLoadingServices(peripheral: self)
					}
				}
			}
		}
	}

	
	//=============================================================================================
	//MARK:	 Delegate - Characteristic

	public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		if self.shouldLoadService(service: service) {
			self.findOrCreateService(cbService: service)?.updateCharacteristics()
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		if self.shouldLoadService(service: characteristic.service) {
			self.findOrCreateService(cbService: characteristic.service)?.didLoad(characteristic: characteristic, error: error)
		} else {
			print("^^^^^^^^^^ Not loading: \(characteristic)")
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		self.characteristicFromCBCharacteristic(characteristic: characteristic)?.didWriteValue(error: error)
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		self.characteristicFromCBCharacteristic(characteristic: characteristic)?.didUpdateNotifyValue()
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
		self.characteristicFromCBCharacteristic(characteristic: characteristic)?.loadDescriptors()
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
		self.characteristicFromCBCharacteristic(characteristic: descriptor.characteristic)?.didUpdateValueForDescriptor(descriptor: descriptor)
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
		self.characteristicFromCBCharacteristic(characteristic: descriptor.characteristic)?.didWriteValueForDescriptor(descriptor: descriptor)
	}
	
	//=============================================================================================
	//MARK: For overriding

	
	public func shouldLoadService(service: CBService?) -> Bool {
		guard let uuid = service?.uuid else { return false }
		if let pertinent = self.pertinentServices {
			return pertinent.contains(uuid)
		}
		return true
	}
}

