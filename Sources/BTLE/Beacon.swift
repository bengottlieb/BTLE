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
	let firstSeenAt: Date
	var lastSeenAt: Date?
	
	class func beacon(with data: NSData) -> BTLEBeacon? {
		if let info = BTLEBeacon.parse(data: data) {
			
			if let existing = BTLEBeacon.existing[info.0] {
				existing.lastSeenAt = Date()
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
		firstSeenAt = Date()
		lastSeenAt = Date()
	}
	
	var description: String {
		let formatter = DateIntervalFormatter()
		formatter.timeStyle = .none
		
		
		let lastSeen = formatter.string(from: self.lastSeenAt!, to: Date())
		
		return "\(self.proximityID), last seen \(lastSeen)"
	}
	
	class func parse(data: NSData) -> (String, Int, Int)? {
		if data.length != 25 { return nil }
		
		let ids = UnsafeMutablePointer<UInt16>.allocate(capacity: 3)
		let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)
		
		data.getBytes(&ids[0], length: 2)
		data.getBytes(&ids[1], range: NSRange(location: 20, length: 2))
		data.getBytes(&ids[2], range: NSRange(location: 22, length: 2))
		
		let companyID = ids[0]
		let major = ids[1]
		let minor = ids[2]
		
		data.getBytes(raw, range: NSRange(location: 4, length: 16))
		let proximityID = NSUUID(uuidBytes: raw)
		
		print("raw: \(raw): \(proximityID), major: \(companyID), minor: \(minor)")
		return (proximityID.uuidString, Int(major), Int(minor))
	}
}
