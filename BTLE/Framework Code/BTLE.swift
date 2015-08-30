//
//  BTLE.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/9/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth


public enum DebugLevel: Int { case None, Low, Medium, High, SuperHigh }

public class BTLE: NSObject {
	public static var manager = BTLE()
	public static var scanner = BTLECentralManager()
	public static var advertiser = BTLEPeripheralManager()
	
	public enum LoadingState { case NotLoaded, Loading, Loaded, LoadingCancelled, Reloading }
	public enum ServiceFilter { case CoreBluetooth, AdvertisingData, ActualServices }

	public enum State: Int { case Off, StartingUp, Active, Idle, PowerInterupted
		var stringValue: String {
			switch (self) {
			case .Off: return "off"
			case .StartingUp: return "starting up"
			case .Active: return "active"
			case .Idle: return "idle"
			case .PowerInterupted: return "interupted by power-off"
			}
		}
	}
	
	static public var debugLevel: DebugLevel = .None
	
	//[CBUUID(string: "FFF0")] //[BatteryServiceCBUUID, UserDataServiceCBUUID, GenericServiceCBUUID, GenericAccessServiceCBUUID, CBUUID(string: "1810"), CBUUID(string: "1805"), CBUUID(string: "1818"), CBUUID(string: "1816"), CBUUID(string: "180A"), CBUUID(string: "1808"), CBUUID(string: "1809"), CBUUID(string: "180D"), CBUUID(string: "1812"), CBUUID(string: "1802"), CBUUID(string: "1803"), CBUUID(string: "1819"), CBUUID(string: "1807"), CBUUID(string: "180E"), CBUUID(string: "1806"), CBUUID(string: "1813"), CBUUID(string: "1804")]
	
	public var services: [CBUUID] = [] { didSet {
		if oldValue != self.services {
			if BTLE.debugLevel != .None { print("Setting services to \(self.services)") }
			self.cycleScanning()
		}
	}}
	public var serviceFilter = ServiceFilter.CoreBluetooth { didSet { if oldValue != self.serviceFilter { self.cycleScanning() }}}
	public var monitorRSSI = false { didSet { self.cycleScanning() }}
	public var disableRSSISmoothing = false
	public var deviceLifetime: NSTimeInterval = 0.0 { didSet {
		Array(BTLE.scanner.peripherals).map({ $0.updateVisibilityTimer(); })
	}}
	public var loadEncryptedCharacteristics = false
	
	public struct notifications {
		public static let willStartScan = "com.standalone.btle.willStartScan"
		public static let didFinishScan = "com.standalone.btle.didFinishScan"

		public static let willStartAdvertising = "com.standalone.btle.willStartAdvertising"
		public static let didFinishAdvertising = "com.standalone.btle.didFinishAdvertising"

		public static let peripheralWasDiscovered = "com.standalone.btle.peripheralWasDiscovered"
		public static let peripheralDidConnect = "com.standalone.btle.peripheralDidConnect"
		public static let peripheralDidDisconnect = "com.standalone.btle.peripheralDidDisconnect"
		public static let peripheralDidUpdateRSSI = "com.standalone.btle.peripheralDidUpdateRSSI"
		public static let peripheralDidUpdateAdvertisementData = "com.standalone.btle.peripheralDidUpdateAdvertisementData"
		public static let peripheralDidUpdateName = "com.standalone.btle.peripheralDidUpdateName"
		public static let peripheralDidLoseComms = "com.standalone.btle.peripheralDidLoseComms"
		public static let peripheralDidRegainComms = "com.standalone.btle.peripheralDidRegainComms"
		
		
		public static let peripheralDidFinishLoading = "com.standalone.btle.peripheralDidLoad"
		public static let peripheralDidBeginLoading = "com.standalone.btle.peripheralBeginLoading"

		public static let characteristicListeningChanged = "com.standalone.btle.characteristicListeningChanged"
		public static let characteristicDidUpdate = "com.standalone.btle.characteristicDidUpdate"
		
		public static let characteristicWasWrittenTo = "com.standalone.btle.characteristicWasWrittenTo"
		public static let characteristicDidFinishWritingBack = "com.standalone.btle.characteristicDidFinishWritingBack"
	}
	
	struct registeredClasses {
		static var services: [CBUUID: BTLEService.Type] = [:]
		static var peripheralClass: BTLEPeripheral.Type?
	}
	
	public class func registerServiceClass(serviceClass: BTLEService.Type, forServiceID serviceID: CBUUID) {
		BTLE.registeredClasses.services[serviceID] = serviceClass
	}
	
	public class func registerPeripheralClass(peripheralClass: BTLEPeripheral.Type?) {
		BTLE.registeredClasses.peripheralClass = peripheralClass
	}

	public class var advertiseInBackground: Bool {
		if let infoDict = NSBundle.mainBundle().infoDictionary, modes = infoDict["UIBackgroundModes"] as? [String] {
			return modes.contains("bluetooth-peripheral")
		}
		
		return false
	}
	
	public class var browseInBackground: Bool {
		if let infoDict = NSBundle.mainBundle().infoDictionary, modes = infoDict["UIBackgroundModes"] as? [String] {
			return modes.contains("bluetooth-central")
		}

		return false
	}
	
	
	
	var cyclingScanning = false
	var cyclingAdvertising = false
	
	public func cycleAdvertising() {
		if self.cyclingAdvertising { return }
		
		switch BTLE.advertiser.state {
		case .Active: fallthrough
		case .StartingUp: fallthrough
		case .PowerInterupted: fallthrough
		case .Idle:
			self.cyclingAdvertising = true
			BTLE.advertiser.turnOff()
			
		case .Off:
			BTLE.advertiser.startAdvertising()
		}
	}
	
	public func cycleScanning() {
		if self.cyclingScanning { return }
		
		switch BTLE.scanner.state {
		case .Active: fallthrough
		case .StartingUp: fallthrough
		case .PowerInterupted: fallthrough
		case .Idle:
			self.cyclingScanning = true
			BTLE.scanner.turnOff()
			
		case .Off:
			BTLE.scanner.startScanning()
		}
	}
	
	//BTLE Authorization status
	public var isAuthorized: Bool { return CBPeripheralManager.authorizationStatus() == .Authorized }
	public func authorizeWithCompletion(completion: (Bool) -> Void) { self.authorizer = BTLEAuthorizer(completion: completion) }

	class BTLEAuthorizer: NSObject, CBPeripheralManagerDelegate {
		init(completion comp: (Bool) -> Void) {
			completion = comp
			super.init()
			self.manager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
			self.manager.startAdvertising(nil)
		}
		let completion: (Bool) -> Void
		var manager: CBPeripheralManager!
		func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager!) {
			if CBPeripheralManager.authorizationStatus() == .Denied {
				self.completion(false)
				self.manager.stopAdvertising()
				BTLE.manager.authorizer = nil
			} else if CBPeripheralManager.authorizationStatus() == .Authorized {
				self.completion(true)
				self.manager.stopAdvertising()
				BTLE.manager.authorizer = nil
			}
		}
	}
	var authorizer: BTLEAuthorizer?
}

func >(lhs: DebugLevel, rhs: DebugLevel) -> Bool { return lhs.rawValue > rhs.rawValue }
func <(lhs: DebugLevel, rhs: DebugLevel) -> Bool { return lhs.rawValue < rhs.rawValue }

public func btle_delay(delay: Double?, closure: () -> ()) {
	if let delay = delay {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC))), dispatch_get_main_queue(), closure)
	} else {
		closure()
	}
}

public func btle_dispatch_main(closure: () -> ()) {
	dispatch_async(dispatch_get_main_queue(), closure)
}
