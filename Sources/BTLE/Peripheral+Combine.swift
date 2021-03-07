//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 3/6/21.
//

import CoreBluetooth

extension BTLEPeripheral {
	public enum Ignored: Int { case not, blackList, missingServices, checkingForServices }
	public enum State: String { case discovered, connecting, connected, disconnecting, undiscovered, unknown
		var description: String { return self.rawValue }
	}
	public typealias RSSValue = Int
	public enum Distance: Int { case touching, veryClose, close, nearby, sameRoom, around, far, unknown
		init(raw: RSSValue) {
			if raw > rssi_range_touching { self = .touching }
			else if raw > rssi_range_very_close { self = .veryClose }
			else if raw > rssi_range_close { self = .close }
			else if raw > rssi_range_nearby { self = .nearby }
			else if raw > rssi_range_same_room { self = .sameRoom }
			else if raw > rssi_range_around { self = .around }
			else { self = .far }
		}
		
		public var toString: String {
			switch self {
			case .touching: return "touching"
			case .veryClose: return "very close"
			case .close: return "close"
			case .nearby: return "nearby"
			case .sameRoom: return "same room"
			case .around: return "around"
			case .far: return "far"
			case .unknown: return "unknown distance"
			}
		}
		
		public var toFloat: Float {
			switch self {
			case .touching: return 0.0
			case .veryClose: return 0.1
			case .close: return 0.25
			case .nearby: return 0.4
			case .sameRoom: return 0.5
			case .around: return 0.75
			case .far: return 0.9
			case .unknown: return 1.0
			}
		}
	}
}

func !=(lhs: [String: Any], rhs: [String: Any]) -> Bool {
	return false
}


#if canImport(Combine)
import Combine

@available(OSX 10.15, iOS 13.0, tvOS 13, watchOS 6, *)
extension BTLEPeripheral {
	public func connect(reloadServices: Bool = false, services: [CBUUID]? = nil, timeout: TimeInterval? = nil) -> AnyPublisher<BTLEPeripheral, Error> {
		Future<BTLEPeripheral, Error> { promise in
			self.connect(reloadServices: reloadServices, services: services, timeout: timeout) { error in
				if let error = error {
					promise(.failure(error))
				} else {
					promise(.success(self))
				}
			}
		}
		.eraseToAnyPublisher()
	}

	public func batteryLevel() -> AnyPublisher<Double, Error> {
		Future<Double, Error> { promise in
			guard let service = self.service(with: .battery) else {
				promise(.failure(PeripheralError.serviceNotFound))
				return
			}
			
			guard let chr = service.characteristic(with: .batteryLevel) else {
				promise(.failure(PeripheralError.characteristicNotFound))
				return
			}

			let data = chr.dataValue
			guard let byte = data?.first else {
				promise(.failure(PeripheralError.noCharacteristicData))
				return
			}
			promise(.success(Double(byte) / 100))
		}
		.eraseToAnyPublisher()
	}
}
#endif
