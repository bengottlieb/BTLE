//
//  BTLE.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/9/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

let AlertServiceCBUUID = CBUUID(string: "1811")
let BatteryServiceCBUUID = CBUUID(string: "180F")
let RunningServiceCBUUID = CBUUID(string: "1814")
let UserDataServiceCBUUID = CBUUID(string: "181C")
let GenericServiceCBUUID = CBUUID(string: "1801")
let GenericAccessServiceCBUUID = CBUUID(string: "1800")

var BTLE_Debugging = false

public class BTLE: NSObject {
	public class var manager: BTLE { struct s { static let manager = BTLE() }; return s.manager }
	public enum LoadingState { case NotLoaded, Loading, Loaded, LoadingCancelled }

	public enum State { case Off, StartingUp, Active, Idle }
	
	public class var debugging: Bool {
		get { return BTLE_Debugging }
		set { BTLE_Debugging = newValue }
	}
	
	public var peripherals: [BTLEPeripheral] = []
	public var scanningState: State = .Off { didSet {
		self.scanner.changingState = true
		switch self.scanningState {
		case .Off: break
		case .StartingUp:
			break
			
		case .Active:
			self.scanner.startScanning()
			
		case .Idle:
			self.scanner.stopScanning()
			
		}
		self.scanner.changingState = false
	}}
	
	public var advertisingState: State = .Off { didSet {
		self.advertiser.changingState = true
		
		switch self.advertisingState {
		case .Off: fallthrough
		case .StartingUp: break
			
		case .Active:
			self.advertiser.startAdvertising()
		case .Idle:
			self.advertiser.stopAdvertising()
		}
		
		self.advertiser.changingState = false
	}}

	
	//[CBUUID(string: "FFF0")] //[BatteryServiceCBUUID, UserDataServiceCBUUID, GenericServiceCBUUID, GenericAccessServiceCBUUID, CBUUID(string: "1810"), CBUUID(string: "1805"), CBUUID(string: "1818"), CBUUID(string: "1816"), CBUUID(string: "180A"), CBUUID(string: "1808"), CBUUID(string: "1809"), CBUUID(string: "180D"), CBUUID(string: "1812"), CBUUID(string: "1802"), CBUUID(string: "1803"), CBUUID(string: "1819"), CBUUID(string: "1807"), CBUUID(string: "180E"), CBUUID(string: "1806"), CBUUID(string: "1813"), CBUUID(string: "1804")]
	
	public var services: [CBUUID] = [] { didSet { self.scanner.updateScan() }}
	public var monitorRSSI = false { didSet { self.scanner.updateScan() }}
	public var deviceLifetime: NSTimeInterval = 0.0 { didSet {
		self.peripherals.map({ $0.updateVisibilityTimer(); })
	}}
	
	
	public struct notifications {
		public static let willStartScan = "com.standalone.btle.willStartScan"
		public static let didFinishScan = "com.standalone.btle.didFinishScan"
		public static let didDiscoverPeripheral = "com.standalone.btle.didDiscoverPeripheral"
		
		public static let peripheralDidConnect = "com.standalone.btle.peripheralDidConnect"
		public static let peripheralDidDisconnect = "com.standalone.btle.peripheralDidDisconnect"
		public static let peripheralDidUpdateRSSI = "com.standalone.btle.peripheralDidUpdateRSSI"
		public static let peripheralDidUpdateAdvertisementData = "com.standalone.btle.peripheralDidUpdateAdvertisementData"
		public static let peripheralDidUpdateName = "com.standalone.btle.peripheralDidUpdateName"
		public static let peripheralDidLoseComms = "com.standalone.btle.peripheralDidLoseComms"
		public static let peripheralDidRegainComms = "com.standalone.btle.peripheralDidRegainComms"
		
		
		public static let peripheralDidFinishLoading = "com.standalone.btle.peripheralDidLoad"
		public static let peripheralDidBeginLoading = "com.standalone.btle.peripheralBeginLoading"

		public static let characteristicDidUpdate = "com.standalone.btle.characteristicDidUpdate"

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
}