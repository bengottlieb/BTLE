//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 3/6/21.
//

import Foundation
import CoreBluetooth

public extension CBUUID {
	static let deviceInfo = CBUUID(string: "0x180A")
	
	static let iOSContinuity = CBUUID(string: "D0611E78-BBB4-4591-A5F8-487910AE4366")

	static let battery = CBUUID(string: "180F")
	static let currentTime = CBUUID(string: "1805")
	static let alert = CBUUID(string: "1811")
	static let running = CBUUID(string: "1814")
	static let userData = CBUUID(string: "181C")
	static let generic = CBUUID(string: "1801")
	static let genericAccess = CBUUID(string: "1800")


}

public extension CBUUID {
	static let serialNumber = CBUUID(string: "0x2A25")
	static let modelNumber = CBUUID(string: "0x2A24")
	static let firmwareVersion = CBUUID(string: "0x2A26")
	static let hardwareRevision = CBUUID(string: "0x2A27")
	static let softwareRevision = CBUUID(string: "0x2A28")
	static let manufacturersName = CBUUID(string: "0x2A29")
	static let regulatoryCertificationData = CBUUID(string: "0x2A2A")
	static let pnpID = CBUUID(string: "0x2A50")
	static let batteryLevel = CBUUID(string: "0x2A19")
}




