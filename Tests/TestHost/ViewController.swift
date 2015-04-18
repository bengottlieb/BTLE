//
//  ViewController.swift
//  BTLE
//
//  Created by Ben Gottlieb on 2/9/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import BTLE
import SA_Swift

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	@IBOutlet var tableView: UITableView!
	@IBOutlet var scanSwitch: UISwitch!
	@IBOutlet var monitorRSSISwitch: UISwitch!

	var devices: [BTLEPeripheral] = []
	
	func reload() {
		self.devices = BTLE.manager.peripherals
		dispatch_async_main {
			self.tableView.reloadData()
		}
	}
	
	var timer: NSTimer?
	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		
		if true {
			self.startAdvertising()
		} else {
			self.startScanning()
		}
	}
	
	func startAdvertising() {
		BTLE.manager.peripheralState = .Active
	}
	
	func startScanning() {
		BTLE.manager.deviceLifetime = 20.0
		BTLE.manager.centralState = .Active
		self.scanSwitch.on = BTLE.manager.centralState == .Active || BTLE.manager.centralState == .StartingUp
		self.monitorRSSISwitch.on = BTLE.manager.monitorRSSI
		
		self.addAsObserver(BTLE.notifications.peripheralDidDisconnect, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.peripheralDidConnect, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.didDiscoverPeripheral, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.peripheralDidUpdateRSSI, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.peripheralDidBeginLoading, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.peripheralDidFinishLoading, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.peripheralDidUpdateName, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.peripheralDidLoseComms, selector: "reload", object: nil)
		self.addAsObserver(BTLE.notifications.peripheralDidRegainComms, selector: "reload", object: nil)
		
		self.timer = NSTimer.scheduledTimerWithTimeInterval(5.0, target: self, selector: "reload", userInfo: nil, repeats: true)
	}
	
	@IBAction func toggleScanning() {
		BTLE.manager.centralState = self.scanSwitch.on ? .Active : .Idle

	}

	@IBAction func toggleRSSIMonitoring() {
		BTLE.manager.monitorRSSI = !BTLE.manager.monitorRSSI
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
		var cell = UITableViewCell(style: .Subtitle, reuseIdentifier: "cell")
		var device = self.devices[indexPath.row]
		
		cell.textLabel?.text = "\(device.summaryDescription)"

		var toggle = UISwitch(frame: CGRectZero)
		toggle.on = device.state == .Connected || device.state == .Connecting
		toggle.tag = indexPath.row
		toggle.addTarget(self, action: "connectToggled:", forControlEvents: .ValueChanged)
		
		cell.accessoryView = toggle
		
		var seconds = Int(abs(device.lastCommunicatedAt.timeIntervalSinceNow))
		cell.detailTextLabel?.text = "\(seconds) sec since last ping, \(device.services.count) services"
		
		if device.state == .Undiscovered {
			cell.textLabel?.textColor = UIColor.redColor()
		}
		
		return cell
	}
	
	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		var device = self.devices[indexPath.row]
		
		println("\(device.fullDescription)")
	}

}


