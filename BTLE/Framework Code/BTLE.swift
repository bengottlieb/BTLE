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

public class BTLE: NSObject {
	public class var manager: BTLE { struct s { static let manager = BTLE() }; return s.manager }
	public enum LoadingState { case NotLoaded, Loading, Loaded, LoadingCancelled }

	public enum State { case Off, StartingUp, Scanning, Idle }
	
	public var peripherals: [Peripheral] = []
	public var state: State = .Off { didSet {
		self.central.changingState = true
		switch self.state {
		case .Off: break
		case .StartingUp:
			break
			
		case .Scanning:
			self.central.startScanning()
			
		case .Idle:
			self.central.stopScanning()
			
		}
		self.central.changingState = false
	}}
	

	
	//[CBUUID(string: "FFF0")] //[BatteryServiceCBUUID, UserDataServiceCBUUID, GenericServiceCBUUID, GenericAccessServiceCBUUID, CBUUID(string: "1810"), CBUUID(string: "1805"), CBUUID(string: "1818"), CBUUID(string: "1816"), CBUUID(string: "180A"), CBUUID(string: "1808"), CBUUID(string: "1809"), CBUUID(string: "180D"), CBUUID(string: "1812"), CBUUID(string: "1802"), CBUUID(string: "1803"), CBUUID(string: "1819"), CBUUID(string: "1807"), CBUUID(string: "180E"), CBUUID(string: "1806"), CBUUID(string: "1813"), CBUUID(string: "1804")]
	
	public var services: [CBUUID] = [] { didSet { self.central.updateScan() }}
	public var monitorRSSI = false { didSet { self.central.updateScan() }}
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
		public static let peripheralDidUpdateName = "com.standalone.btle.peripheralDidUpdateName"
		public static let peripheralDidLoseComms = "com.standalone.btle.peripheralDidLoseComms"
		public static let peripheralDidRegainComms = "com.standalone.btle.peripheralDidRegainComms"
		
		
		public static let peripheralDidFinishLoading = "com.standalone.btle.peripheralDidLoad"
		public static let peripheralDidBeginLoading = "com.standalone.btle.peripheralBeginLoading"

		public static let characteristicDidUpdate = "com.standalone.btle.characteristicDidUpdate"

	}
	
	

	public lazy var central: Central = { return Central() }()
}