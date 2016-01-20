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
import GulliverEXT

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	static var instance: AppDelegate!
	
	static let beaconProximityIDKey = DefaultsKey<String>("bcn-proximityID")
	static let beaconMajorIDKey = DefaultsKey<String>("bcn-majorID")
	static let beaconMinorIDKey = DefaultsKey<String>("bcn-minorID")
	static let beaconEnabledKey = DefaultsKey<Bool>("bcn-enabled")
	
	var window: UIWindow?


	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		// Override point for customization after application launch
		
		AppDelegate.instance = self
		
		let settings = UIUserNotificationSettings(forTypes: [.Alert, .Sound, .Badge], categories: nil)
		application.registerUserNotificationSettings(settings)
		application.registerForRemoteNotifications()
	
		//BTLE.manager.services = [CBUUID(string: "01EB2EF1-BF82-4516-81BE-57E119207437")]
		
		BTLE.manager.serviceFilter = .ActualServices
		self.addAsObserver(BTLE.notifications.characteristicWasWrittenTo, selector: "zapped:")
		
		self.setupBeacon()
		return true
	}
	
	var beacon: CLBeaconRegion?
	
	func setupBeacon() {
		if NSUserDefaults.get(AppDelegate.beaconEnabledKey) ?? false {
			guard let uuid = NSUUID(UUIDString: NSUserDefaults.get(AppDelegate.beaconProximityIDKey)) else {
				NSUserDefaults.set(false, forKey: AppDelegate.beaconEnabledKey)
				UIAlertController.showAlert("Unable to Start an iBeacon: Invalid UUID")
				return
			}
			
			let major = CLBeaconMajorValue(NSUserDefaults.get(AppDelegate.beaconMajorIDKey)) ?? 0
			let minor = CLBeaconMajorValue(NSUserDefaults.get(AppDelegate.beaconMinorIDKey)) ?? 0
			let name = UIDevice.currentDevice().name
			
			self.beacon = CLBeaconRegion(proximityUUID:  uuid, major: major, minor: minor, identifier: name)
			
			let data = self.beacon!.peripheralDataWithMeasuredPower(nil)
			if data.count > 0 {
				print("Starting to advertise (\(uuid)) beacon: \(data)")
				BTLE.advertiser.advertisingData = NSDictionary(dictionary: data) as? [String: AnyObject] ?? [:]
			}
			BTLE.advertiser.startAdvertising()
		} else if self.beacon != nil {
			BTLE.advertiser.stopAdvertising()
			self.beacon = nil
		}
	}

	func applicationWillResignActive(application: UIApplication) {
	}

	func applicationDidEnterBackground(application: UIApplication) {
	}

	func applicationWillEnterForeground(application: UIApplication) {
	}

	func applicationDidBecomeActive(application: UIApplication) {
	}

	func applicationWillTerminate(application: UIApplication) {
	}

	func zapped(note: NSNotification) {
		print("received write requests: \(note.object)")
		
//		SoundEffect.playSound("zap.caf")
//		UILocalNotification.playSound("zap.caf")
		
	}
}

class LockPeripheral: BTLEPeripheral {
	required init(peripheral: CBPeripheral, RSSI: BTLEPeripheral.RSSValue?, advertisementData adv: [NSObject: AnyObject]?) {
		super.init(peripheral: peripheral, RSSI: RSSI, advertisementData: adv)
	}
	required init() { super.init() }
}

let LockStatusCharacteristic = CBUUID(string: "FFF3")

class LockService: BTLEService {
	required init(service svc: CBService, onPeriperhal: BTLEPeripheral) {
		super.init(service: svc, onPeriperhal: onPeriperhal)
	}
	
	override func didFinishLoading() {
//		let lockStatus = self.characteristicWithUUID(LockStatusCharacteristic)
//		let data = lockStatus?.dataValue
		//lockStatus?.listenForUpdates = true
		
		
		//print("BTLEService: \(lockStatus), Data: \(data)")
	}
}

extension UILocalNotification {
	class func playSound(soundName: String) {
		let note = UILocalNotification()
		
		note.fireDate = NSDate(timeIntervalSinceNow: 0.01)
		note.soundName = soundName
		UIApplication.sharedApplication().scheduleLocalNotification(note)
	}
}