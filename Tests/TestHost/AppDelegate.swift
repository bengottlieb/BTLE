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

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?


	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		// Override point for customization after application launch
		
		
		//BTLE.manager.services = [CBUUID(string: "01EB2EF1-BF82-4516-81BE-57E119207436")]
		
		return true
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


}

class LockPeripheral: BTLEPeripheral {
	required init(peripheral: CBPeripheral, RSSI: Int?, advertisementData adv: [NSObject: AnyObject]?) {
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
		var lockStatus = self.characteristicWithUUID(LockStatusCharacteristic)
		var data = lockStatus?.dataValue
		lockStatus?.listenForUpdates = true
		
		
		println("BTLEService: \(lockStatus), Data: \(data)")
	}
}