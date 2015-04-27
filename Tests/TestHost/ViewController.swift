//
//  ViewController.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/9/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import BTLE
import CoreBluetooth
import SA_Swift

let testServiceID = CBUUID(string: "FFF3")
let filterServiceID = CBUUID(string: "FFF3")

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	@IBOutlet var tableView: UITableView!
	@IBOutlet var scanSwitch: UISwitch!
	@IBOutlet var monitorRSSISwitch: UISwitch!
	@IBOutlet var advertiseSwitch: UISwitch!
	@IBOutlet var filterByServicesSwitch: UISwitch!

	var characteristicData = NSDate().localTimeString(timeStyle: .FullStyle)
	var devices: [BTLEPeripheral] = []
	
	func reload() {
		self.devices = Array(BTLE.manager.scanner.peripherals)
		dispatch_async_main {
			self.tableView.reloadData()
		}
	}
	
	var notifyCharacteristic: BTLEMutableCharacteristic?
	var writableCharacteristic: BTLEMutableCharacteristic?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		self.tableView.registerNib(UINib(nibName: "PeripheralCellTableViewCell", bundle: nil), forCellReuseIdentifier: "cell")
		
		BTLE.debugging = true
		BTLE.registerServiceClass(LockService.self, forServiceID: CBUUID(string: "FFF4"))
		BTLE.registerPeripheralClass(LockPeripheral.self)

		//setup scanner
		BTLE.manager.deviceLifetime = 20.0
		BTLE.manager.scanningState = (NSUserDefaults.keyedBool("scanning") ?? false) ? .Active : .Off
		BTLE.manager.monitorRSSI = (NSUserDefaults.keyedBool("monitorRSSI") ?? false)
		BTLE.manager.services = (NSUserDefaults.keyedBool("filterByServices") ?? false) ? [] : [filterServiceID]
		
		//setup advertiser
		
		self.writableCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "FFF5"), properties: CBCharacteristicProperties.Read | CBCharacteristicProperties.Write, value: nil)
		self.notifyCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "FFF4"), properties: CBCharacteristicProperties.Read | CBCharacteristicProperties.Notify, value: self.characteristicData.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true))
		
		var service = BTLEMutableService(uuid: testServiceID, isPrimary: true, characteristics: [ self.writableCharacteristic!, self.notifyCharacteristic! ])
		service.advertised = true
		
		BTLE.manager.advertiser.addService(service)
		BTLE.manager.advertisingState = (NSUserDefaults.keyedBool("advertising") ?? false) ? .Active : .Off
		
		self.scanSwitch.on = BTLE.manager.scanningState == .Active || BTLE.manager.scanningState == .StartingUp
		self.advertiseSwitch.on = BTLE.manager.advertisingState == .Active || BTLE.manager.advertisingState == .StartingUp
		self.filterByServicesSwitch.on = BTLE.manager.services.count > 0
		self.monitorRSSISwitch.on = BTLE.manager.monitorRSSI

		self.filterByServicesSwitch.enabled = self.scanSwitch.on
		self.monitorRSSISwitch.enabled = self.scanSwitch.on

		self.addAsObserver(BTLE.notifications.willStartScan, selector: "updateStatus", object: nil)
		self.addAsObserver(BTLE.notifications.didFinishScan, selector: "updateStatus", object: nil)

		self.addAsObserver(BTLE.notifications.willStartAdvertising, selector: "updateStatus", object: nil)
		self.addAsObserver(BTLE.notifications.didFinishAdvertising, selector: "updateStatus", object: nil)

	
		self.addAsObserver(BTLE.notifications.peripheralWasDiscovered, selector: "reload", object: nil)
		
		self.updateStatus()
	}
	
	func updateStatus() {
		if BTLE.manager.scanningState == .Active {
			self.timer = NSTimer.scheduledTimerWithTimeInterval(5.0, target: self, selector: "reload", userInfo: nil, repeats: true)
		} else {
			self.timer?.invalidate()
			self.timer = nil
		}
		
		self.reload()
		UIApplication.sharedApplication().idleTimerDisabled = (BTLE.manager.scanningState == .Active || BTLE.manager.advertisingState == .Active)
	}
	
	var timer: NSTimer?
	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		self.navigationController?.navigationBarHidden = true
	}
	
	@IBAction func toggleScanning() {
		BTLE.manager.scanningState = self.scanSwitch.on ? .Active : .Idle
		NSUserDefaults.setKeyedBool(self.scanSwitch.on, forKey: "scanning")

		self.filterByServicesSwitch.enabled = self.scanSwitch.on
		self.monitorRSSISwitch.enabled = self.scanSwitch.on
	}

	@IBAction func toggleRSSIMonitoring() {
		BTLE.manager.monitorRSSI = self.monitorRSSISwitch.on
		NSUserDefaults.setKeyedBool(self.monitorRSSISwitch.on, forKey: "monitorRSSI")
	}
	
	@IBAction func toggleAdvertising() {
		BTLE.manager.advertisingState = self.advertiseSwitch.on ? .Active : .Idle
		NSUserDefaults.setKeyedBool(self.advertiseSwitch.on, forKey: "advertising")
	}
	
	@IBAction func toggleFilterByServices() {
		var active = BTLE.manager.scanningState == .Active || BTLE.manager.scanningState == .StartingUp
		
		if (active) { BTLE.manager.scanningState = .Idle }
		NSUserDefaults.setKeyedBool(self.filterByServicesSwitch.on, forKey: "filterByServices")
		BTLE.manager.services = self.filterByServicesSwitch.on ? [filterServiceID] : []
		if (active) { BTLE.manager.scanningState = .Active }
	}
	
	@IBAction func configureServices() {
		self.characteristicData = NSDate().localTimeString(timeStyle: .FullStyle)
		
		var published = self.characteristicData.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)
		
		self.notifyCharacteristic!.updateDataValue(published)
	}
	
	func connectToggled(toggle: UISwitch) {
		var device = self.devices[toggle.tag]
		
		if toggle.on {
			device.connect()
		} else {
			device.disconnect()
		}
		
		self.tableView.beginUpdates()
		self.tableView.reloadRowsAtIndexPaths([ NSIndexPath(forRow: toggle.tag, inSection: 0)], withRowAnimation: .Automatic)
		self.tableView.endUpdates()
	}
	
	//=============================================================================================
	//MARK:
	
	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return self.devices.count
	}
	
	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		var cell = tableView.dequeueReusableCellWithIdentifier("cell", forIndexPath: indexPath) as! PeripheralCellTableViewCell
		var device = self.devices[indexPath.row]
		
		cell.peripheral = device
		
		return cell
	}
	
	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		var device = self.devices[indexPath.row]
		
		self.navigationController?.pushViewController(DeviceDetailsViewController(peripheral: device), animated: true)
	}
	
	func tableView(tableView: UITableView, titleForDeleteConfirmationButtonForRowAtIndexPath indexPath: NSIndexPath) -> String! {
		return "Ignore"
	}
	
	func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
		tableView.beginUpdates()
		
		tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
		var device = self.devices[indexPath.row]
		
		device.ignored = true
		self.devices = Array(BTLE.manager.scanner.peripherals)
		
		tableView.endUpdates()
	}

	func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
		var device = self.devices[indexPath.row]
		
		return 71.0 + CGFloat(max(device.advertisementData.count - 2, 0)) * 15.0
	}
	
	@IBAction func nearby() {
		self.presentViewController(NearbyPeripheralsViewController().navigationWrappedController(hideNavigationBar: false), animated: true, completion: nil)
	}
}


