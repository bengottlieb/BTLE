//
//  BTLEPeripheral.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/13/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

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

public struct BTLEServiceUUIDs {
	public static let deviceInfo = CBUUID(string: "0x180A")
	
	public static let iOSContinuity = CBUUID(string: "D0611E78-BBB4-4591-A5F8-487910AE4366")

	public static let battery = CBUUID(string: "180F")
	public static let currentTime = CBUUID(string: "1805")
	public static let alert = CBUUID(string: "1811")
	public static let running = CBUUID(string: "1814")
	public static let userData = CBUUID(string: "181C")
	public static let generic = CBUUID(string: "1801")
	public static let genericAccess = CBUUID(string: "1800")


}

public struct BTLECharacteristicUUIDs {
	public static let serialNumber = CBUUID(string: "0x2A25")
	public static let modelNumber = CBUUID(string: "0x2A24")
	public static let firmwareVersion = CBUUID(string: "0x2A26")
	public static let hardwareRevision = CBUUID(string: "0x2A27")
	public static let softwareRevision = CBUUID(string: "0x2A28")
	public static let manufacturersName = CBUUID(string: "0x2A29")
	public static let regulatoryCertificationData = CBUUID(string: "0x2A2A")
	public static let pnpID = CBUUID(string: "0x2A50")
}



open class BTLEPeripheral: NSObject, CBPeripheralDelegate {
	deinit {
		self.connectionTimeoutTimer?.invalidate()
		BTLE.debugLog(.superHigh, "BTLE Peripheral: deiniting: \(self)")
	}
	public enum Ignored: Int { case not, blackList, missingServices, checkingForServices }
	public enum State { case discovered, connecting, connected, disconnecting, undiscovered, unknown
		var description: String {
			switch self {
			case .discovered: return "Discovered"
			case .connecting: return "Connecting"
			case .connected: return "Connected"
			case .disconnecting: return "Disconnecting"
			case .undiscovered: return "Undiscovered"
			case .unknown: return "Unknown"
			}
		}
	}
	public typealias RSSValue = Int
	public enum Distance: Int { case touching, veryClose, close, nearby, sameRoom, around, far, unknown
		init(raw: RSSValue) {
			if raw > rssi_range_touching { self = .touching }
			else if raw > rssi_range_very_close { self = .veryClose }
			else if raw > rssi_range_close { self = .close }
			else if raw > rssi_range_nearby { self = .nearby }
			else if raw > rssi_range_same_room { self = .sameRoom }
			else if raw > rssi_range_around { self = .around }
			else { self = .far }
		}
		
		public var toString: String {
			switch self {
			case .touching: return "touching"
			case .veryClose: return "very close"
			case .close: return "close"
			case .nearby: return "nearby"
			case .sameRoom: return "same room"
			case .around: return "around"
			case .far: return "far"
			case .unknown: return "unknown"
			}
		}

		public var toFloat: Float {
			switch self {
			case .touching: return 0.0
			case .veryClose: return 0.1
			case .close: return 0.25
			case .nearby: return 0.4
			case .sameRoom: return 0.5
			case .around: return 0.75
			case .far: return 0.9
			case .unknown: return 1.0
			}
		}
	}
	
	public var cbPeripheral: CBPeripheral!
	public var uuid: UUID!
	public var name: String!
	public var lastCommunicatedAt = Date() { didSet {
		if self.state == .undiscovered {
			self.state = .discovered
			self.sendNotification(name: BTLE.notifications.peripheralDidRegainComms)
		}
		btle_delay(0.001) { self.updateVisibilityTimer() }
	}}
	public var loadingState = BTLE.LoadingState.notLoaded {
		didSet {
			if self.loadingState == .loaded {
				self.sendNotification(name: BTLE.notifications.peripheralDidFinishLoading)
				BTLE.debugLog(.medium, "BTLE Peripheral: Loaded: \(self.fullDescription)")
				self.sendConnectionCompletions(error: nil)
			}
		}
	}
	public var services: [BTLEService] = []
	public var advertisementData: [String: Any] = [:] { didSet {
		if self.advertisementData != oldValue {
			self.sendNotification(name: BTLE.notifications.peripheralDidUpdateAdvertisementData)
		}
	}}
	
	func didFailToConnect(error: Error?) {
		BTLE.debugLog(.medium, "Failed to connect \(self.name): \(error)")
		self.sendConnectionCompletions(error: error)
	}
	
	func sendConnectionCompletions(error: Error?) {
		self.connectionTimeoutTimer?.invalidate()
		BTLE.debugLog(.medium, "Sending \(self.connectionCompletionBlocks.count) completion messages (\(error))")
		let completions = self.connectionCompletionBlocks
		self.connectionCompletionBlocks = []
		
		for block in completions {
			block(error)
		}
	}
	
	public var state: State = .discovered { didSet {
		if self.state == oldValue { return }
	
		BTLE.debugLog(.medium, "Changing state on \(self.name), \(oldValue.description) -> \(self.state.description)")
	
		switch self.state {
		case .connected:
			self.updateRSSI()
			self.reloadServices()
			
			
		case .disconnecting: fallthrough
		case .discovered:
			self.cancelLoad()
			
		case .undiscovered:
			self.disconnect()
			
		default: break
		}
	}}
	public var rssi: RSSValue? { didSet {
		self.lastCommunicatedAt = Date()
		self.sendNotification(name: BTLE.notifications.peripheralDidUpdateRSSI)
	}}
	public var rawRSSI: RSSValue?
	
	public var distance: Distance { if let rssi = self.rssi { return Distance(raw: rssi) }; return .unknown }
	
	public var rssiHistory: [(Date, RSSValue)] = []
	func setCurrentRSSI(newRSSI: RSSValue) {
		if abs(newRSSI) == 127 { return }
		
		self.rawRSSI = newRSSI
		if BTLE.manager.disableRSSISmoothing {
			self.rssi = newRSSI
		} else {
			self.rssiHistory.append((Date(), newRSSI))
			if self.rssiHistory.count > BTLE.manager.rssiSmoothingHistoryDepth { self.rssiHistory.remove(at: 0) }
			
			self.rssi = self.rssiHistory.reduce(0, { $0 + $1.1 }) / self.rssiHistory.count
		}
		self.lastCommunicatedAt = Date()
	}
	
	public override required init() {
		super.init()
	}
	
	public required init(peripheral: CBPeripheral, RSSI: RSSValue?, advertisementData adv: [String: Any]?) {
		BTLE.debugLog(.high, "Peripheral: creating from \(peripheral)")
		
		cbPeripheral = peripheral
		uuid = peripheral.identifier
		name = peripheral.name ?? "unknown"
		if let adv = adv {
			advertisementData = adv
		}
		
		super.init()

		peripheral.delegate = self
		peripheral.readRSSI()
		self.rssi = RSSI
		self.updateVisibilityTimer()

		if BTLE.scanner.ignoredPeripheralUUIDs.contains(peripheral.identifier.uuidString) {
			ignored = .blackList
			BTLE.debugLog(.medium, "Peripheral: Ignoring: \(name), \(uuid)")
		} else if BTLE.manager.services.count > 0 {
			if BTLE.manager.serviceFilter == .advertisingData {
				if let info = adv {
					self.updateIgnoredWithAdvertisingData(info: info)
				} else {
					self.ignored = .missingServices
				}
			} else if BTLE.manager.serviceFilter == .actualServices {
				self.ignored = .checkingForServices
				self.connect()
			}
		}
		
		if self.ignored == .not {
			BTLE.debugLog(.medium, "BTLE Peripheral: not ignored: \(self)")
		}
	}
	
	func updateIgnoredWithAdvertisingData(info: [String: Any]) {
		BTLE.scanner.dispatchQueue.async {
			if BTLE.manager.serviceFilter == .advertisingData && BTLE.manager.services.count > 0 {
				var ignored = true
				if let services = info[CBAdvertisementDataServiceUUIDsKey] as? NSArray {
					for service in services {
						if let cbid = service as? CBUUID {
							if BTLE.manager.services.contains(cbid) { ignored = false; break }
						}
					}
				}
				if ignored {
					self.ignored = .missingServices
					BTLE.debugLog(.superHigh, "BTLE Peripheral: ignored \(self.cbPeripheral.name) with advertising info: \(info)")
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
	 
	public func connectionTimedOut() {
		self.state = .discovered
		self.sendConnectionCompletions(error: NSError(type: .peripheralConnectionTimedOut))
	}
	
	public func connect(reloadServices: Bool = false, timeout: TimeInterval? = nil, completion: ((Error?) -> ())? = nil) {
		BTLE.scanner.dispatchQueue.async {
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
					btle_dispatch_main {
						self.connectionTimeoutTimer = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(
							self.connectionTimedOut), userInfo: nil, repeats: false)
					}
				}
				if (reloadServices) { self.loadingState = .reloading }
				BTLE.debugLog(.medium, "Attempting to connect to \(self.name), current state: \(self.state.description)")
				self.state = .connecting
				BTLE.scanner.cbCentral.connect(self.cbPeripheral, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
			}
		}
	}
	
	public func disconnect() {
		BTLE.debugLog(.medium, "Disconnecting from \(self.name), current state: \(self.state.description)")
		if self.state == .connected { self.state = .disconnecting }
		
		BTLE.scanner.cbCentral?.cancelPeripheralConnection(self.cbPeripheral)
	}
	
	func cancelLoad() {
		BTLE.scanner.dispatchQueue.async {
			if self.loadingState == .loading {
				BTLE.debugLog(.medium, "Aborting service load on \(self.name)")
				self.loadingState = .loadingCancelled
			}
			
			for svc in self.services { svc.cancelLoad() }
		}
	}
	
	public var ignored: Ignored = .not {
		didSet {
			if oldValue != self.ignored {
				if self.ignored == .blackList {
					BTLE.scanner.addIgnoredPeripheral(peripheral: self)
				} else if self.ignored == .not {
					BTLE.scanner.removeIgnoredPeripheral(peripheral: self)
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
	
	public func updateRSSI() {
		self.cbPeripheral.readRSSI()
	}
	
	public func serviceWithUUID(uuid: CBUUID) -> BTLEService? { return self.services.filter({ $0.cbService.uuid == uuid }).last }
	public func characteristicFromCBCharacteristic(characteristic: CBCharacteristic) -> BTLECharacteristic? {
		if let service = self.serviceWithUUID(uuid: characteristic.service.uuid) {
			if let chr = service.characteristicWithUUID(uuid: characteristic.uuid) {
				return chr
			}
		}
		BTLE.debugLog(.high, "Unabled to find characteristic \(characteristic) \(self.name), current state: \(self.state.description)")
		return nil
	}
	
	public func reloadServices() {
		BTLE.scanner.dispatchQueue.async {
			BTLE.debugLog(.high, "Loading services on \(self.name)")
			self.services = []
			if self.ignored == .checkingForServices {
				self.cbPeripheral.discoverServices(nil)
			} else {
				self.cbPeripheral.discoverServices(nil)
			}
		}
	}
	
	//=============================================================================================
	//MARK: Internal
	func loadServices(services: [BTLEService]) {
		self.sendNotification(name: BTLE.notifications.peripheralDidBeginLoading)
		self.loadingState = .loading
		for service in services {
			service.reload()
		}
	}
	
	func didFinishLoadingService(service: BTLEService) {
		BTLE.scanner.dispatchQueue.async {
			BTLE.debugLog(.medium, "BTLE Peripheral: Finished loading \(service.uuid), \(self.numberOfLoadingServices) left")
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

	@discardableResult func findOrCreateService(cbService: CBService) -> BTLEService {
		if let service = self.serviceWithUUID(uuid: cbService.uuid) {
			return service
		}
		
		let service = BTLEService.createService(service: cbService, onPeriperhal: self)
		self.services.append(service)

		return service
	}
	
	//=============================================================================================
	//MARK: Timeout

	weak var visibilityTimer: Timer?
	@discardableResult func updateVisibilityTimer() -> Timer? {
		self.visibilityTimer?.invalidate()
		self.visibilityTimer = nil
		
		if self.state == .discovered && BTLE.manager.deviceLifetime > 0 {
			btle_dispatch_main { [weak self] in
				if let me = self {
					let timeSinceLastComms = abs(me.lastCommunicatedAt.timeIntervalSinceNow)
					if BTLE.manager.deviceLifetime > timeSinceLastComms {
						let timeoutInverval = (BTLE.manager.deviceLifetime - timeSinceLastComms)
						
						// if timeoutInverval < 3 { println("BTLE Peripheral: short term timer: \(timeSinceLastComms) sec") }
						
						me.visibilityTimer?.invalidate()
						btle_dispatch_main {
							me.visibilityTimer = Timer.scheduledTimer(timeInterval: timeoutInverval, target: me, selector: #selector(BTLEPeripheral.disconnectDueToTimeout), userInfo: nil, repeats: false)
						}
					} else if BTLE.manager.deviceLifetime > 0 {
						me.disconnectDueToTimeout()
					}
				}
			}
			
		}
		
		return nil
	}
	
	func disconnectDueToTimeout() {
		BTLE.scanner.dispatchQueue.async {
			self.visibilityTimer?.invalidate()
			self.visibilityTimer = nil
			
			if self.state == .discovered {
				self.state = .undiscovered
				self.sendNotification(name: BTLE.notifications.peripheralDidLoseComms)
			}
		}
	}
	
	func sendNotification(name: Notification.Name) {
		if self.ignored != .blackList { Notification.postOnMainThread(name: name, object: self) }
	}

	//=============================================================================================
	//MARK: Delegate - Peripheral
	
	public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		self.rssi = RSSI.intValue
	}

	public func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
		BTLE.scanner.dispatchQueue.async {
			self.name = peripheral.name
			self.sendNotification(name: BTLE.notifications.peripheralDidUpdateName)
			BTLE.debugLog(.medium, "Peripheral: Updated name for: \(self.name)")
		}
	}

	//=============================================================================================
	//MARK: Delegate - Service
	public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
		BTLE.scanner.dispatchQueue.async {
			for invalidated in invalidatedServices {
				if self.shouldLoadService(service: invalidated) {
					self.findOrCreateService(cbService: invalidated).reload()
				}
			}
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		BTLE.scanner.dispatchQueue.async {
			BTLE.debugLog(.medium, "Discovered \(self.cbPeripheral.services?.count ?? 0) on \(self.name)")
			
			if let services = self.cbPeripheral.services {
				if self.ignored == .checkingForServices {
					for svc in services {
						BTLE.debugLog(.medium, "\(self.name) loading \(svc.uuid)")
						if BTLE.manager.services.contains(svc.uuid) {
							self.ignored = .not
							BTLE.scanner.pendingPeripheralFinishLoadingServices(peripheral: self)
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
						BTLE.scanner.pendingPeripheralFinishLoadingServices(peripheral: self)
					}
				}
			}
		}
	}

	
	//=============================================================================================
	//MARK:	 Delegate - Characteristic

	public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		if self.shouldLoadService(service: service) {
			self.findOrCreateService(cbService: service).updateCharacteristics()
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		if self.shouldLoadService(service: characteristic.service) {
			self.findOrCreateService(cbService: characteristic.service).didLoadCharacteristic(chr: characteristic, error: error)
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

	
	public func shouldLoadService(service: CBService) -> Bool {
		return true
	}
}

func !=(lhs: [String: Any], rhs: [String: Any]) -> Bool {
	return false
}

