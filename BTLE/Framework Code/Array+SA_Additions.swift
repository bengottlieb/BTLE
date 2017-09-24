//
//  String+SA_Additions.swift
//  Simplify
//
//  Created by Ben Gottlieb on 9/3/14.
//  Copyright (c) 2014 Stand Alone, Inc. All rights reserved.
//

import Foundation

extension Array {
	func shuffled() -> [Element] {
		var list = self
		for i in 0..<(list.count - 1) {
			let j = Int(arc4random_uniform(UInt32(list.count - i))) + i
			list.swapAt(i, j)
		}
		return list
	}

}

extension Set {
	func map<U>(transform: (Element) -> U) -> Set<U> {
		return Set<U>(self.map(transform))
	}
}
