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
import Gulliver

let testServiceID = CBUUID(string: "01EB2EF1-BF82-4516-81BE-57E119207436") // CBUUID(string: "737CFF0D-7AEC-43B6-A37F-1EC1671307A6")
let filterServiceID = CBUUID(string: "45DFE33C-312F-4CEF-A67C-E103D29FA41D")//CBUUID(string: "FEAA")//testServiceID// CBUUID(string: "C9563739-1783-4E81-A3EC-5061D4B2311C")

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	@IBOutlet var tableView: UITableView!
	@IBOutlet var scanSwitch: UISwitch!
	@IBOutlet var monitorRSSISwitch: UISwitch!
	@IBOutlet var advertiseSwitch: UISwitch!
	@IBOutlet var filterByServicesSwitch: UISwitch!
	@IBOutlet var scanningLabel: UILabel!
	@IBOutlet var beaconButton: UIBarButtonItem!

	var characteristicData = NSDate().localTimeString(timeStyle: .FullStyle)
	var devices: [BTLEPeripheral] = []
	
	func reload() {
		self.devices = Array(BTLE.scanner.peripherals).sort { $0.rssi > $1.rssi }
		
		dispatch_async_main {
			self.tableView.reloadData()
			self.updateScanningLabel()
			self.scanSwitch.on = BTLE.scanner.state == .Active || BTLE.scanner.state == .StartingUp
		}
	}
		
	var notifyCharacteristic: BTLEMutableCharacteristic?
	var writableCharacteristic: BTLEMutableCharacteristic?
	
	func updateScanningLabel() {
		var text = BTLE.scanner.state.stringValue
		let count = self.devices.count
		
		text += " \(count) found"
		
		self.scanningLabel.text = text
	}
	
	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		
		if NSUserDefaults.get(AppDelegate.beaconEnabledKey) {
			self.beaconButton.title  = "iBeacon: On"
		} else {
			self.beaconButton.title  = "iBeacon…"
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		if self.tableView.tableHeaderView == nil { self.tableView.tableHeaderView = self.tableView.tableFooterView }
		self.tableView.registerNib(UINib(nibName: "PeripheralCellTableViewCell", bundle: nil), forCellReuseIdentifier: "cell")
		
		BTLE.debugLevel = .High
//		BTLE.registerServiceClass(LockService.self, forServiceID: CBUUID(string: "FFF4"))
//		BTLE.registerPeripheralClass(LockPeripheral.self)

		//setup scanner
		BTLE.manager.deviceLifetime = 20.0
		BTLE.manager.ignoreBeaconLikeDevices = false
		BTLE.manager.monitorRSSI = (NSUserDefaults.get(DefaultsKey<Bool>("monitorRSSI")) ?? false)
		BTLE.manager.services = (NSUserDefaults.get(DefaultsKey<Bool>("filterByServices")) ?? false) ? [filterServiceID] : []
		BTLE.manager.serviceFilter = .AdvertisingData
		
		if (NSUserDefaults.get(DefaultsKey<Bool>("scanning")) ?? false) {
			BTLE.scanner.startScanning()
		} else {
			BTLE.scanner.stopScanning()
		}
		
		//setup advertiser
		
		
//		self.writableCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "C9563739-1783-4E81-A3EC-5061D4B2311C"), properties: [CBCharacteristicProperties.Write, CBCharacteristicProperties.Read], value: nil, permissions: [.Readable, .Writeable])
//		self.notifyCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "FFF4"), properties: [CBCharacteristicProperties.Read, CBCharacteristicProperties.Notify], value: self.characteristicData.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true))
//		
//		let service = BTLEMutableService(uuid: testServiceID, isPrimary: true, characteristics: [ self.writableCharacteristic! ])
//		service.advertised = true
//		
//		BTLE.advertiser.addService(service)
//		if (NSUserDefaults.get(DefaultsKey<Bool>("advertising")) ?? false) {
//			BTLE.advertiser.startAdvertising()
//		}
		
		self.scanSwitch.on = BTLE.scanner.state == .Active || BTLE.scanner.state == .StartingUp
		self.advertiseSwitch.on = BTLE.advertiser.state == .Active || BTLE.advertiser.state == .StartingUp
		self.filterByServicesSwitch.on = BTLE.manager.services.count > 0
		self.monitorRSSISwitch.on = BTLE.manager.monitorRSSI

		//self.filterByServicesSwitch.enabled = self.scanSwitch.on
		//self.monitorRSSISwitch.enabled = self.scanSwitch.on

		self.addAsObserver(BTLE.notifications.willStartScan, selector: "updateStatus", object: nil)
		self.addAsObserver(BTLE.notifications.didStartScan, selector: "updateStatus", object: nil)
		self.addAsObserver(BTLE.notifications.didFinishScan, selector: "updateStatus", object: nil)

		self.addAsObserver(BTLE.notifications.willStartAdvertising, selector: "updateStatus", object: nil)
		self.addAsObserver(BTLE.notifications.didFinishAdvertising, selector: "updateStatus", object: nil)

	
		self.addAsObserver(BTLE.notifications.peripheralWasDiscovered, selector: "reload", object: nil)
		
		self.updateStatus()
	}
	
	func updateStatus() {
		if BTLE.scanner.state == .Active {
			self.timer = NSTimer.scheduledTimerWithTimeInterval(5.0, target: self, selector: "reload", userInfo: nil, repeats: true)
		} else {
			self.timer?.invalidate()
			self.timer = nil
		}
		
		self.reload()
		UIApplication.sharedApplication().idleTimerDisabled = (BTLE.scanner.state == .Active || BTLE.advertiser.state == .Active)
	}
	
	var timer: NSTimer?
	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		self.navigationController?.navigationBarHidden = true
	}
	
	@IBAction func toggleScanning() {
		if (self.scanSwitch.on) {
			BTLE.scanner.startScanning()
		} else {
			BTLE.scanner.stopScanning()
		}

		NSUserDefaults.set(self.scanSwitch.on, forKey: DefaultsKey<Bool>("scanning"))

		self.filterByServicesSwitch.enabled = self.scanSwitch.on
		self.monitorRSSISwitch.enabled = self.scanSwitch.on
	}

	@IBAction func toggleRSSIMonitoring() {
		BTLE.manager.monitorRSSI = self.monitorRSSISwitch.on
		NSUserDefaults.set(self.monitorRSSISwitch.on, forKey: DefaultsKey<Bool>("monitorRSSI"))
	}
	
	@IBAction func toggleAdvertising() {
		if self.advertiseSwitch.on {
			self.writableCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "C9563739-1783-4E81-A3EC-5061D4B2311C"), properties: [CBCharacteristicProperties.Write, CBCharacteristicProperties.Read], value: nil, permissions: [.Readable, .Writeable])
			self.notifyCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "FFF4"), properties: [CBCharacteristicProperties.Read, CBCharacteristicProperties.Notify], value: self.characteristicData.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true))

			let service = BTLEMutableService(uuid: testServiceID, isPrimary: true, characteristics: [ self.writableCharacteristic! ])
			service.advertised = true
			BTLE.advertiser.addService(service)
			BTLE.advertiser.startAdvertising()
		} else {
			BTLE.advertiser.stopAdvertising()
		}
		NSUserDefaults.set(self.advertiseSwitch.on, forKey: DefaultsKey<Bool>("advertising"))
	}
	
	@IBAction func toggleFilterByServices() {
		NSUserDefaults.set(self.filterByServicesSwitch.on, forKey: DefaultsKey<Bool>("filterByServices"))
		BTLE.manager.services = self.filterByServicesSwitch.on ? [filterServiceID] : []
	}
	
	@IBAction func configureServices() {
		self.characteristicData = NSDate().localTimeString(timeStyle: .FullStyle)
		
		let published = self.characteristicData.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)
		
		self.notifyCharacteristic!.updateDataValue(published)
	}
	
	func connectToggled(toggle: UISwitch) {
		let device = self.devices[toggle.tag]
		
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
		let cell = tableView.dequeueReusableCellWithIdentifier("cell", forIndexPath: indexPath) as! PeripheralCellTableViewCell
		let device = self.devices[indexPath.row]
		
		cell.peripheral = device
		
		return cell
	}
	
	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		let device = self.devices[indexPath.row]
		
		self.navigationController?.pushViewController(DeviceDetailsViewController(peripheral: device), animated: true)
	}
	
	func tableView(tableView: UITableView, titleForDeleteConfirmationButtonForRowAtIndexPath indexPath: NSIndexPath) -> String? {
		return "Ignore"
	}
	
	func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
		tableView.beginUpdates()
		
		tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
		let device = self.devices[indexPath.row]
		
		device.ignore()
		self.devices = Array(BTLE.scanner.peripherals)
		
		tableView.endUpdates()
	}

	func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
		if indexPath.row >= self.devices.count { return 0 }
		let device = self.devices[indexPath.row]
		
		return 71.0 + CGFloat(max(device.advertisementData.count - 2, 0)) * 15.0
	}
	
	@IBAction func nearby() {
		self.presentViewController(NearbyPeripheralsViewController().navigationWrappedController(false), animated: true, completion: nil)
	}
	
	@IBAction func showBeaconSettings() {
		BeaconSettingsViewController.presentInController(self)
	}
}


