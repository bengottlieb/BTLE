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
import GulliverUI

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

	var characteristicData = Date().localTimeString(timeStyle: .full)
	var devices: [BTLEPeripheral] = []
	
	func reload() {
		self.devices = Array(BTLE.scanner.peripherals).sorted { ($0.rssi ?? 0) > ($1.rssi ?? 0) }
		
		DispatchQueue.main.async {
			self.tableView.reloadData()
			self.updateScanningLabel()
			self.scanSwitch.isOn = BTLE.scanner.state == .active || BTLE.scanner.state == .startingUp
		}
	}
		
	var notifyCharacteristic: BTLEMutableCharacteristic?
	var writableCharacteristic: BTLEMutableCharacteristic?
	
	func updateScanningLabel() {
		var text = BTLE.scanner.state.stringValue
		let count = self.devices.count
		
		text = "\(count) found"
		
		self.scanningLabel.text = text
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		if UserDefaults.get(key: AppDelegate.beaconEnabledKey) {
			self.beaconButton.title  = "iBeacon: On"
		} else {
			self.beaconButton.title  = "iBeacon…"
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		if self.tableView.tableHeaderView == nil { self.tableView.tableHeaderView = self.tableView.tableFooterView }
		self.tableView.register(UINib(nibName: "PeripheralCellTableViewCell", bundle: nil), forCellReuseIdentifier: "cell")
		
		BTLE.debugLevel = .high
//		BTLE.registerServiceClass(LockService.self, forServiceID: CBUUID(string: "FFF4"))
//		BTLE.registerPeripheralClass(LockPeripheral.self)

		//setup scanner
		BTLE.manager.deviceLifetime = 20.0
		BTLE.manager.ignoreBeaconLikeDevices = false
		BTLE.manager.monitorRSSI = (UserDefaults.get(key: DefaultsKey<Bool>("monitorRSSI")))
		BTLE.manager.serviceIDsToScanFor = (UserDefaults.get(key: DefaultsKey<Bool>("filterByServices"))) ? AppDelegate.servicesToScanFor : []
		BTLE.manager.serviceFilter = .coreBluetooth
		
		if (UserDefaults.get(key: DefaultsKey<Bool>("scanning"))) {
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
//		if (UserDefaults.get(DefaultsKey<Bool>("advertising")) ?? false) {
//			BTLE.advertiser.startAdvertising()
//		}
		
		self.scanSwitch.isOn = BTLE.scanner.state == .active || BTLE.scanner.state == .startingUp
		self.advertiseSwitch.isOn = BTLE.advertiser.state == .active || BTLE.advertiser.state == .startingUp
		self.filterByServicesSwitch.isOn = BTLE.manager.serviceIDsToScanFor.count > 0
		self.monitorRSSISwitch.isOn = BTLE.manager.monitorRSSI

		//self.filterByServicesSwitch.enabled = self.scanSwitch.on
		//self.monitorRSSISwitch.enabled = self.scanSwitch.on

		self.addAsObserver(for: BTLE.notifications.willStartScan, selector: #selector(updateStatus), object: nil)
		self.addAsObserver(for: BTLE.notifications.didStartScan, selector: #selector(updateStatus), object: nil)
		self.addAsObserver(for: BTLE.notifications.didFinishScan, selector: #selector(updateStatus), object: nil)

		self.addAsObserver(for: BTLE.notifications.willStartAdvertising, selector: #selector(updateStatus), object: nil)
		self.addAsObserver(for: BTLE.notifications.didFinishAdvertising, selector: #selector(updateStatus), object: nil)

	
		self.addAsObserver(for: BTLE.notifications.peripheralWasDiscovered, selector: #selector(reload), object: nil)
		
		self.updateStatus()
	}
	
	func updateStatus() {
		if BTLE.scanner.state == .active {
			DispatchQueue.main.async {
				self.timer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(ViewController.reload), userInfo: nil, repeats: true)
			}
		} else {
			self.timer?.invalidate()
			self.timer = nil
		}
		
		self.reload()
		UIApplication.shared.isIdleTimerDisabled = (BTLE.scanner.state == .active || BTLE.advertiser.state == .active)
	}
	
	var timer: Timer?
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		self.navigationController?.isNavigationBarHidden = true
	}
	
	@IBAction func toggleScanning() {
		if (self.scanSwitch.isOn) {
			BTLE.scanner.startScanning()
		} else {
			BTLE.scanner.stopScanning()
		}

		UserDefaults.set(self.scanSwitch.isOn, forKey: DefaultsKey<Bool>("scanning"))

		self.filterByServicesSwitch.isEnabled = self.scanSwitch.isOn
		self.monitorRSSISwitch.isEnabled = self.scanSwitch.isOn
	}

	@IBAction func toggleRSSIMonitoring() {
		BTLE.manager.monitorRSSI = self.monitorRSSISwitch.isOn
		UserDefaults.set(self.monitorRSSISwitch.isOn, forKey: DefaultsKey<Bool>("monitorRSSI"))
	}
	
	@IBAction func toggleAdvertising() {
		if self.advertiseSwitch.isOn {
			self.writableCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "C9563739-1783-4E81-A3EC-5061D4B2311C"), properties: [CBCharacteristicProperties.write, CBCharacteristicProperties.read], value: nil, permissions: [.readable, .writeable])
			self.notifyCharacteristic = BTLEMutableCharacteristic(uuid: CBUUID(string: "FFF4"), properties: [CBCharacteristicProperties.read, CBCharacteristicProperties.notify], value: self.characteristicData.data(using: .utf8, allowLossyConversion: true))

			let service = BTLEMutableService(uuid: testServiceID, isPrimary: true, characteristics: [ self.writableCharacteristic! ])
			service.advertised = true
			BTLE.advertiser.add(service: service)
			BTLE.advertiser.startAdvertising()
		} else {
			BTLE.advertiser.stopAdvertising()
		}
		UserDefaults.set(self.advertiseSwitch.isOn, forKey: DefaultsKey<Bool>("advertising"))
	}
	
	@IBAction func toggleFilterByServices() {
		UserDefaults.set(self.filterByServicesSwitch.isOn, forKey: DefaultsKey<Bool>("filterByServices"))
		BTLE.manager.serviceIDsToScanFor = self.filterByServicesSwitch.isOn ? AppDelegate.servicesToScanFor : []
	}
	
	@IBAction func configureServices() {
		self.characteristicData = Date().localTimeString(timeStyle: .full)
		
		let published = self.characteristicData.data(using: .utf8, allowLossyConversion: true)
		
		self.notifyCharacteristic!.updateDataValue(data: published)
	}
	
	func connectToggled(toggle: UISwitch) {
		let device = self.devices[toggle.tag]
		
		if toggle.isOn {
			device.connect(services: AppDelegate.servicesToRead)
		} else {
			device.disconnect()
		}
		
		self.tableView.beginUpdates()
		self.tableView.reloadRows(at: [ IndexPath(row: toggle.tag, section: 0)], with: .automatic)
		self.tableView.endUpdates()
	}
	
	//=============================================================================================
	//MARK:
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return self.devices.count
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! PeripheralCellTableViewCell
		let device = self.devices[indexPath.row]
		
		cell.peripheral = device
		
		return cell
	}
	
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let device = self.devices[indexPath.row]
		
		self.navigationController?.pushViewController(DeviceDetailsViewController(peripheral: device), animated: true)
	}
	
	func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
		return "Ignore"
	}
	
	func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
		tableView.beginUpdates()
		
		tableView.deleteRows(at: [indexPath], with: .automatic)
		let device = self.devices[indexPath.row]
		
		device.ignore()
		self.devices = Array(BTLE.scanner.peripherals)
		
		tableView.endUpdates()
	}

	func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if indexPath.row >= self.devices.count { return 0 }
		let device = self.devices[indexPath.row]
		
		return 71.0 + CGFloat(max(device.advertisementData.count - 2, 0)) * 15.0
	}
	
	@IBAction func nearby() {
		self.present(NearbyPeripheralsViewController().navigationWrappedController(false), animated: true, completion: nil)
	}
	
	@IBAction func showBeaconSettings() {
		BeaconSettingsViewController.presentInController(parent: self)
	}
}


