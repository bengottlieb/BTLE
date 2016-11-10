//
//  BTLE+Errors.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/5/16.
//  Copyright © 2016 Stand Alone, inc. All rights reserved.
//

import Foundation

let BTLEErrorDomain = "BTLE Framework"

extension NSError {
	enum BTLEErrorType: String { case characteristicHasPendingWriteInProgress = "Unable to write to the characteristic, there's already a write in progress", characteristicNotWritable = "This characteristic cannot be written to", characteristicNotConnected = "Characteristic Not Connected", peripheralConnectionTimedOut = "Connection to Peripheral Timed Out"
	
	}
	
	
	convenience init(type: BTLEErrorType, userInfo: [String: Any] = [:]) {
		var info = userInfo
		info[NSLocalizedDescriptionKey] = type.rawValue
		self.init(domain: BTLEErrorDomain, code: type.rawValue.hash, userInfo: info)
	}
}
