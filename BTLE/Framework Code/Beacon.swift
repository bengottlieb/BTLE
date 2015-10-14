//
//  Beacon.swift
//  BTLE
//
//  Created by Ben Gottlieb on 10/12/15.
//  Copyright © 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth


class BTLEBeacon: CustomStringConvertible {
	static var existing: [String: BTLEBeacon] = [:]
	
	let proximityID: String
	let major: Int
	let minor: Int
	let firstSeenAt: NSDate
	var lastSeenAt: NSDate?
	
	class func beaconWithData(data: NSData) -> BTLEBeacon? {
		if let info = BTLEBeacon.parseData(data) {
			
			if let existing = BTLEBeacon.existing[info.0] {
				existing.lastSeenAt = NSDate()
				print("Existing beacon: \(existing.proximityID)")
				return existing
			}
			
			existing[info.0] = BTLEBeacon(id: info.0, maj: info.1, min: info.2)
		}
		return nil
	}
	
	init(id: String, maj: Int, min: Int) {
		proximityID = id
		major = maj
		minor = min
		firstSeenAt = NSDate()
		lastSeenAt = NSDate()
	}
	
	var description: String {
		let formatter = NSDateIntervalFormatter()
		formatter.timeStyle = .NoStyle
		
		
		let lastSeen = formatter.stringFromDate(self.lastSeenAt!, toDate: NSDate())
		
		return "\(self.proximityID), last seen \(lastSeen)"
	}
	
	class func parseData(data: NSData) -> (String, Int, Int)? {
		if data.length != 25 { return nil }
		
		let ids = UnsafeMutablePointer<UInt16>.alloc(3)
		let raw = UnsafeMutablePointer<UInt8>.alloc(16)
		
		data.getBytes(&ids[0], length: 2)
		data.getBytes(&ids[1], range: NSRange(location: 20, length: 2))
		data.getBytes(&ids[2], range: NSRange(location: 22, length: 2))
		
		let companyID = ids[0]
		let major = ids[1]
		let minor = ids[2]
		
		data.getBytes(raw, range: NSRange(location: 4, length: 16))
		let proximityID = NSUUID(UUIDBytes: raw)
		
		print("raw: \(raw): \(proximityID), major: \(companyID), minor: \(minor)")
		return (proximityID.UUIDString, Int(major), Int(minor))
	}
}