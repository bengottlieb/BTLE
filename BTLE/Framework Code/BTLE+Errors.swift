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
	enum BTLEErrorType: String { case CharacteristicHasPendingWriteInProgress = "Unable to write to the characteristic, there's already a write in progress", CharacteristicNotWritable = "This characteristic cannot be written to", CharacteristicNotConnected = "Characteristic Not Connected"
	
	}
	
	
	convenience init(type: BTLEErrorType, userInfo: [NSObject: AnyObject] = [:]) {
		var info = userInfo ?? [:]
		info[NSLocalizedDescriptionKey] = type.rawValue
		self.init(domain: BTLEErrorDomain, code: type.rawValue.hash, userInfo: info)
	}
}