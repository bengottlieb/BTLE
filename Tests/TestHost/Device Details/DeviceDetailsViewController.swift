//
//  DeviceDetailsViewController.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/19/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import BTLE
import SA_Swift

class DeviceDetailsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	deinit {
		self.removeAsObserver()
	}
	
	let peripheral: BTLEPeripheral
	@IBOutlet var tableView: UITableView!
	@IBOutlet var connectedSwitch: UISwitch!
	
	
	func startLoading() {
		self.tableView.alpha = 0.5
	}

	func finishLoading() {
		dispatch_async_main {
			self.tableView.alpha = 1.0
		}
		self.updateSections()
	}

	init(peripheral per: BTLEPeripheral) {
		peripheral = per
		
		super.init(nibName: "DeviceDetailsViewController", bundle: nil)
		
		self.addAsObserver(BTLE.notifications.peripheralDidBeginLoading, selector: "startLoading")
		self.addAsObserver(BTLE.notifications.peripheralDidFinishLoading, selector: "finishLoading")
		self.updateSections()
	}

	required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	
    override func viewDidLoad() {
        super.viewDidLoad()

		self.connectedSwitch.on = self.peripheral.state == .Connected
        // Do any additional setup after loading the view.
    }
	
	override func viewWillAppear(animated: Bool) {
		self.navigationController?.navigationBarHidden = false
	}

	func updateSections() {
		self.sections = [nil]
		
		for service in self.peripheral.services {
			self.sections.append(service)
		}
		
		dispatch_async_main {
			self.tableView.reloadData()
		}
	}
	
	@IBAction func toggleConnected() {
		if self.connectedSwitch.on {
			self.peripheral.connect()
		} else {
			self.peripheral.disconnect()
		}
	}
	

	
	
	//=============================================================================================
	//MARK: Tableview
	
	var sections: [BTLEService?] = []

	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let service = self.sections[section] {
			return service.characteristics.count
		} else {
			return self.peripheral.advertisementData.count
		}
	}
	
	func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return self.sections.count
	}
	
	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		if let service = self.sections[indexPath.section] {
			var cell = UITableViewCell(style: .Default, reuseIdentifier: "cell")
			
			return cell
 		} else {
			var cell = UITableViewCell(style: .Value1, reuseIdentifier: "cell")
			var info = self.peripheral.advertisementData
			var keys = sorted((info as NSDictionary).allKeys as! [String], <)
			var key = keys[indexPath.row]
			var value = info[key] as? Printable
			
			cell.textLabel?.text = key
			cell.detailTextLabel?.text = (value?.description ?? "").stringByReplacingOccurrencesOfString("\n", withString: "")
			
			return cell
		}
	}
	
	func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if let service = self.sections[section] {
			return service.uuid.UUIDString
		} else {
			return "Advertisement Data"
		}
	}
}
