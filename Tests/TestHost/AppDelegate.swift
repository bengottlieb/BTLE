//
//  AppDelegate.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/9/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import CoreBluetooth
import BTLE
import Gulliver
import CoreLocation
import GulliverUI

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	static var instance: AppDelegate!
	
	static let beaconProximityIDKey = DefaultsKey<String>("bcn-proximityID")
	static let beaconMajorIDKey = DefaultsKey<String>("bcn-majorID")
	static let beaconMinorIDKey = DefaultsKey<String>("bcn-minorID")
	static let beaconEnabledKey = DefaultsKey<Bool>("bcn-enabled")
	
	var window: UIWindow?

	static let parentServiceID = CBUUID(string: "CD1B6256-CCE3-496A-A573-3FCE739A3736")
	static let childServiceID = CBUUID(string: "287E2E84-7B66-445E-8168-9811FB49B12E")
	static let infoServiceID = CBUUID(string: "D4D8A77A-8301-4349-A1AE-402EFF51A098")
	
	static let nameCharacteristicID = CBUUID(string: "0001")
	static let deviceCharacteristicID = CBUUID(string: "0002")
	
	static var serviceToScanFor = CBUUID(string: "287E2E84-7B66-445E-8168-9811FB49B12E")
	static var servicesToRead: [CBUUID]? = [CBUUID(string: "D4D8A77A-8301-4349-A1AE-402EFF51A098")]

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]?) -> Bool {
		// Override point for customization after application launch
		
		AppDelegate.instance = self
		
		let settings = UIUserNotificationSettings(types: [.alert, .sound, .badge], categories: nil)
		application.registerUserNotificationSettings(settings)
		application.registerForRemoteNotifications()
	
		//BTLE.manager.services = [CBUUID(string: "01EB2EF1-BF82-4516-81BE-57E119207437")]
		
		BTLE.manager.serviceFilter = .actualServices
		self.addAsObserver(for: BTLE.notifications.characteristicWasWrittenTo, selector: #selector(zapped))
		
		self.setupBeacon()
		return true
	}
	
	var beacon: CLBeaconRegion?
	
	func setupBeacon() {
//		if UserDefaults.get(key: AppDelegate.beaconEnabledKey) {
//			guard let uuid = UUID(uuidString: UserDefaults.get(key: AppDelegate.beaconProximityIDKey)) else {
//				UserDefaults.set(false, forKey: AppDelegate.beaconEnabledKey)
//				SA_AlertController.showAlert(title: "Unable to Start an iBeacon: Invalid UUID")
//				return
//			}
//			
//			let major = CLBeaconMajorValue(UserDefaults.get(key: AppDelegate.beaconMajorIDKey)) ?? 0
//			let minor = CLBeaconMajorValue(UserDefaults.get(key: AppDelegate.beaconMinorIDKey)) ?? 0
//			let name = UIDevice.current
//				.name
//			
//			self.beacon = CLBeaconRegion(proximityUUID:  uuid, major: major, minor: minor, identifier: name)
//			
//			let data = self.beacon!.peripheralData(withMeasuredPower: nil)
//			if data.count > 0 {
//				print("Starting to advertise (\(uuid)) beacon: \(data)")
//				BTLE.advertisingData = NSDictionary(dictionary: data) as? [String: Any] ?? [:]
//			}
//			BTLE.advertiser.startAdvertising()
//		} else if self.beacon != nil {
//			BTLE.advertiser.stopAdvertising()
//			self.beacon = nil
//		}
	}

	func applicationWillResignActive(_ application: UIApplication) {
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
	}

	func applicationWillTerminate(_ application: UIApplication) {
	}

	func zapped(note: NSNotification) {
		print("received write requests: \(note.object)")
		
//		SoundEffect.playSound("zap.caf")
//		UILocalNotification.playSound("zap.caf")
		
	}
}

class LockPeripheral: BTLEPeripheral {
	required init(peripheral: CBPeripheral, RSSI: BTLEPeripheral.RSSValue?, advertisementData adv: [String: Any]?) {
		super.init(peripheral: peripheral, RSSI: RSSI, advertisementData: adv)
	}
	required init() { super.init() }
}

let LockStatusCharacteristic = CBUUID(string: "FFF3")

class LockService: BTLEService {
	required init(service svc: CBService, onPeriperhal: BTLEPeripheral) {
		super.init(service: svc, onPeriperhal: onPeriperhal)
	}
	
	override public func didFinishLoading() {
//		let lockStatus = self.characteristic(with: LockStatusCharacteristic)
//		let data = lockStatus?.dataValue
		//lockStatus?.listenForUpdates = true
		
		
		//print("BTLEService: \(lockStatus), Data: \(data)")
	}
}

extension UILocalNotification {
	class func playSound(soundName: String) {
		let note = UILocalNotification()
		
		note.fireDate = Date(timeIntervalSinceNow: 0.01)
		note.soundName = soundName
		UIApplication.shared.scheduleLocalNotification(note)
	}
}
