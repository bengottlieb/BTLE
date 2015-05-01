//
//  BTLE.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/9/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth
import SA_Swift


public enum DebugLevel: Int { case None, Low, Medium, High }

public class BTLE: NSObject {
	public class var manager: BTLE { struct s { static let manager = BTLE() }; return s.manager }
	public enum LoadingState { case NotLoaded, Loading, Loaded, LoadingCancelled, Reloading }

	public enum State { case Off, StartingUp, Active, Idle, PowerInterupted
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
	
	public var scanningState: State = .Off { didSet {
		//println("changing scan state to \(self.scanningState.stringValue)")
		self.scanner.stateChangeCounter++
		switch self.scanningState {
		case .Off: break
		case .StartingUp:
			break
			
		case .Active:
			self.scanner.startScanning()
			
		case .Idle:
			self.scanner.stopScanning()
			
		case .PowerInterupted:
			break
			
		}
		self.scanner.stateChangeCounter--
	}}
	
	public var advertisingState: State = .Off { didSet {
		self.advertiser.stateChangeCounter++
		
		switch self.advertisingState {
		case .Off: fallthrough
		case .StartingUp: break
			
		case .Active:
			self.advertiser.startAdvertising()
		case .Idle:
			self.advertiser.stopAdvertising()
			
		case .PowerInterupted: break
		}
		
		self.advertiser.stateChangeCounter--
	}}

	
	//[CBUUID(string: "FFF0")] //[BatteryServiceCBUUID, UserDataServiceCBUUID, GenericServiceCBUUID, GenericAccessServiceCBUUID, CBUUID(string: "1810"), CBUUID(string: "1805"), CBUUID(string: "1818"), CBUUID(string: "1816"), CBUUID(string: "180A"), CBUUID(string: "1808"), CBUUID(string: "1809"), CBUUID(string: "180D"), CBUUID(string: "1812"), CBUUID(string: "1802"), CBUUID(string: "1803"), CBUUID(string: "1819"), CBUUID(string: "1807"), CBUUID(string: "180E"), CBUUID(string: "1806"), CBUUID(string: "1813"), CBUUID(string: "1804")]
	
	public var services: [CBUUID] = [] { didSet { self.scanner.updateScan() }}
	public var monitorRSSI = false { didSet { self.scanner.updateScan() }}
	public var disableRSSISmoothing = false
	public var deviceLifetime: NSTimeInterval = 0.0 { didSet {
		Array(self.scanner.peripherals).map({ $0.updateVisibilityTimer(); })
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

	public lazy var scanner: BTLECentralManager = { return BTLECentralManager() }()
	public lazy var advertiser: BTLEPeripheralManager = { return BTLEPeripheralManager() }()
	
	
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
