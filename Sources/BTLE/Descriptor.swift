//
//  Descriptor.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/21/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import CoreBluetooth

public class BTLEDescriptor {
	public var cbDescriptor: CBDescriptor!
	
	public init(descriptor: CBDescriptor) {
		cbDescriptor = descriptor
	}
}