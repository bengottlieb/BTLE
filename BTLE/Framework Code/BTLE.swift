//
//  BTLE.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/9/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth


public enum DebugLevel: Int { case none, low, medium, high, superHigh }

public class BTLE: NSObject {
	public static var manager = BTLE()
	public static var scanner = BTLECentralManager()
	public static var advertiser = BTLEPeripheralManager()
	
	public enum LoadingState { case notLoaded, loading, loaded, loadingCancelled, reloading }
	public enum ServiceFilter { case coreBluetooth, advertisingData, actualServices }

	public enum State: Int { case off, startingUp, active, idle, powerInterupted, shuttingDown, cycling
		public var stringValue: String {
			switch (self) {
			case .off: return "off"
			case .startingUp: return "starting up"
			case .active: return "active"
			case .idle: return "idle"
			case .powerInterupted: return "interupted by power-off"
			case .shuttingDown: return "Shutting Down"
			case .cycling: return "Cycling"
			}
		}
	}
	
	static public var debugLevel: DebugLevel = .none
	
	//[CBUUID(string: "FFF0")] //[BatteryServiceCBUUID, UserDataServiceCBUUID, GenericServiceCBUUID, GenericAccessServiceCBUUID, CBUUID(string: "1810"), CBUUID(string: "1805"), CBUUID(string: "1818"), CBUUID(string: "1816"), CBUUID(string: "180A"), CBUUID(string: "1808"), CBUUID(string: "1809"), CBUUID(string: "180D"), CBUUID(string: "1812"), CBUUID(string: "1802"), CBUUID(string: "1803"), CBUUID(string: "1819"), CBUUID(string: "1807"), CBUUID(string: "180E"), CBUUID(string: "1806"), CBUUID(string: "1813"), CBUUID(string: "1804")]
	
	public var services: [CBUUID] = [] { didSet {
		if oldValue != self.services {
			BTLE.debugLog(.low, "Setting services to \(self.services)") 
			self.cycleScanning()
		}
	}}
	public var serviceFilter = ServiceFilter.coreBluetooth { didSet { if oldValue != self.serviceFilter { self.cycleScanning() }}}
	public var monitorRSSI = false { didSet { self.cycleScanning() }}
	public var disableRSSISmoothing = false
	public var rssiSmoothingHistoryDepth = 10
	public var deviceLifetime: TimeInterval = 0.0 { didSet {
		Array(BTLE.scanner.peripherals).forEach { $0.updateVisibilityTimer(); }
	}}
	public var loadEncryptedCharacteristics = false
	public var ignoreBeaconLikeDevices = true
	
	class func debugLog(_ requiredLevel: DebugLevel, _ message: @autoclosure () -> String) {
		if self.debugLevel.rawValue >= requiredLevel.rawValue {
			print("BTLE: \(message())")
		}
	}
	
	public struct notifications {
		public static let willStartScan = Notification.Name("com.standalone.btle.willStartScan")
		public static let didStartScan = Notification.Name("com.standalone.btle.didStartScan")
		public static let didFinishScan = Notification.Name("com.standalone.btle.didFinishScan")

		public static let willStartAdvertising = Notification.Name("com.standalone.btle.willStartAdvertising")
		public static let didFinishAdvertising = Notification.Name("com.standalone.btle.didFinishAdvertising")

		public static let peripheralWasDiscovered = Notification.Name("com.standalone.btle.peripheralWasDiscovered")
		public static let peripheralDidConnect = Notification.Name("com.standalone.btle.peripheralDidConnect")
		public static let peripheralDidDisconnect = Notification.Name("com.standalone.btle.peripheralDidDisconnect")
		public static let peripheralDidUpdateRSSI = Notification.Name("com.standalone.btle.peripheralDidUpdateRSSI")
		public static let peripheralDidUpdateAdvertisementData = Notification.Name("com.standalone.btle.peripheralDidUpdateAdvertisementData")
		public static let peripheralDidUpdateName = Notification.Name("com.standalone.btle.peripheralDidUpdateName")
		public static let peripheralDidLoseComms = Notification.Name("com.standalone.btle.peripheralDidLoseComms")
		public static let peripheralDidRegainComms = Notification.Name("com.standalone.btle.peripheralDidRegainComms")
		
		
		public static let peripheralDidFinishLoading = Notification.Name("com.standalone.btle.peripheralDidLoad")
		public static let peripheralDidBeginLoading = Notification.Name("com.standalone.btle.peripheralBeginLoading")

		public static let characteristicListeningChanged = Notification.Name("com.standalone.btle.characteristicListeningChanged")
		public static let characteristicDidUpdate = Notification.Name("com.standalone.btle.characteristicDidUpdate")
		
		public static let characteristicWasWrittenTo = Notification.Name("com.standalone.btle.characteristicWasWrittenTo")
		public static let characteristicDidFinishWritingBack = Notification.Name("com.standalone.btle.characteristicDidFinishWritingBack")
	}
	
	struct registeredClasses {
		static var services: [CBUUID: BTLEService.Type] = [:]
		static var peripheralClass: BTLEPeripheral.Type?
	}
	
	public class func register(class serviceClass: BTLEService.Type, forServiceID serviceID: CBUUID) {
		BTLE.registeredClasses.services[serviceID] = serviceClass
	}
	
	public class func register(peripheralClass: BTLEPeripheral.Type?) {
		BTLE.registeredClasses.peripheralClass = peripheralClass
	}

	public class var advertiseInBackground: Bool {
		if let infoDict = Bundle.main.infoDictionary, let modes = infoDict["UIBackgroundModes"] as? [String] {
			return modes.contains("bluetooth-peripheral")
		}
		
		return false
	}
	
	public class var browseInBackground: Bool {
		if let infoDict = Bundle.main.infoDictionary, let modes = infoDict["UIBackgroundModes"] as? [String] {
			return modes.contains("bluetooth-central")
		}

		return false
	}
	
	
	
	var cyclingScanning = false
	var cyclingAdvertising = false
	
	public func cycleAdvertising() {
		if self.cyclingAdvertising { return }
		
		switch BTLE.advertiser.state {
		case .active: fallthrough
		case .startingUp: fallthrough
		case .powerInterupted: fallthrough
		case .idle:
			self.cyclingAdvertising = true
			BTLE.advertiser.turnOff()
			
		case .shuttingDown: break
		case .cycling: break
			
		case .off:
			BTLE.advertiser.startAdvertising()
		}
	}
	
	public func cycleScanning() {
		BTLE.scanner.internalState = .cycling
	}
	
	//BTLE Authorization status
	public var isAuthorized: Bool { return CBPeripheralManager.authorizationStatus() == .authorized }
	public func authorizeWithCompletion(_ completion: @escaping (Bool) -> Void) { self.authorizer = BTLEAuthorizer(completion: completion) }

	class BTLEAuthorizer: NSObject, CBPeripheralManagerDelegate {
		init(completion comp: @escaping (Bool) -> Void) {
			completion = comp
			super.init()
			self.manager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
			self.manager.startAdvertising(nil)
		}
		let completion: (Bool) -> Void
		var manager: CBPeripheralManager!
		func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
			if CBPeripheralManager.authorizationStatus() == .denied {
				self.completion(false)
				self.manager.stopAdvertising()
				BTLE.manager.authorizer = nil
			} else if CBPeripheralManager.authorizationStatus() == .authorized {
				self.completion(true)
				self.manager.startAdvertising()
				BTLE.manager.authorizer = nil
			}
		}
	}
	var authorizer: BTLEAuthorizer?
}

//func >(lhs: DebugLevel, rhs: DebugLevel) -> Bool { return lhs.rawValue > rhs.rawValue }
//func <(lhs: DebugLevel, rhs: DebugLevel) -> Bool { return lhs.rawValue < rhs.rawValue }

public func btle_delay(_ delay: TimeInterval?, closure: @escaping () -> ()) {
	if let delay = delay {
		DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay, qos: .userInitiated, execute: closure)
	} else {
		closure()
	}
}

public func btle_dispatch_main(closure: @escaping () -> ()) {
	DispatchQueue.main.async(execute: closure)
}
