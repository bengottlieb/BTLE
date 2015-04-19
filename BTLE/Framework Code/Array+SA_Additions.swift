//
//  String+SA_Additions.swift
//  Simplify
//
//  Created by Ben Gottlieb on 9/3/14.
//  Copyright (c) 2014 Stand Alone, Inc. All rights reserved.
//

import Foundation

extension Array {
	func contains<T: Equatable>(obj: T) -> Bool {
		return self.indexOf(obj) != nil
	}

	mutating func remove<U: Equatable>(object: U) -> [T] {
		var index: Int?
		for (idx, objectToCompare) in enumerate(self) {
			if let to = objectToCompare as? U {
				if object == to {
					index = idx
				}
			}
		}
		
		if let found = index { self.removeAtIndex(found) }
		return self
	}
	
	func indexOf<T: Equatable>(obj: T) -> Int? {
		for i in 0..<self.count {
			if let iter = self[i] as? T { if iter == obj { return i } }
		}
		return nil
	}
	
	func shuffled() -> [T] {
		var list = self
		for i in 0..<(list.count - 1) {
			let j = Int(arc4random_uniform(UInt32(list.count - i))) + i
			swap(&list[i], &list[j])
		}
		return list
	}

}

extension Set {
	func map<U>(transform: (T) -> U) -> Set<U> {
		return Set<U>(Swift.map(self, transform))
	}
}
