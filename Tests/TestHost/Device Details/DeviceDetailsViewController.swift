//
//  DeviceDetailsViewController.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/19/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import BTLE
import Gulliver
import GulliverUI

class DeviceDetailsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	deinit {
		self.removeAsObserver()
	}
	
	let peripheral: BTLEPeripheral
	@IBOutlet var tableView: UITableView!
	@IBOutlet var connectedSwitch: UISwitch!
	
	var refreshControl: UIRefreshControl?
	
	
	func startLoading() {
		DispatchQueue.main.async {
			self.refreshControl?.beginRefreshing()
		}
	}

	func finishLoading() {
		DispatchQueue.main.async {
			self.refreshControl?.endRefreshing()
		}
		self.updateSections()
	}

	init(peripheral per: BTLEPeripheral) {
		peripheral = per
		
		super.init(nibName: "DeviceDetailsViewController", bundle: nil)
		
		self.addAsObserver(for: BTLE.notifications.peripheralDidBeginLoading, selector: #selector(startLoading))
		self.addAsObserver(for: BTLE.notifications.peripheralDidFinishLoading, selector: #selector(finishLoading))
		self.addAsObserver(for: BTLE.notifications.peripheralDidConnect, selector: #selector(updateConnectedState))
		self.addAsObserver(for: BTLE.notifications.peripheralDidDisconnect, selector: #selector(updateConnectedState))
		self.updateSections()
		
		self.updateConnectedState()
	}
	
	func updateConnectedState() {
		DispatchQueue.main.async {
			self.tableView?.alpha = (self.peripheral.state == .connected) ? 1.0 : 0.5
			self.title = self.peripheral.name + ((self.peripheral.state == .connected) ? " Connected" : " Disconnected")
			self.connectedSwitch.isOn = (self.peripheral.state == .connected)
		}
	}

	required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	
    override func viewDidLoad() {
        super.viewDidLoad()
		
		self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.connectedSwitch)
		
		self.refreshControl = UIRefreshControl(frame: CGRect.zero)
		self.tableView.addSubview(self.refreshControl!)
		self.refreshControl?.addTarget(self, action: #selector(reloadDevice), for
			
			: .valueChanged)

		self.connectedSwitch.isOn = self.peripheral.state == .connected
		
		self.tableView.register(UINib(nibName: "CharacteristicTableViewCell", bundle: nil), forCellReuseIdentifier: "characteristic")
		
		self.updateConnectedState()
        // Do any additional setup after loading the view.
    }
	
	func reloadDevice() {
		self.peripheral.reloadServices()
	}
	
	override func viewWillAppear(_ animated: Bool) {
		self.navigationController?.isNavigationBarHidden = false
	}

	func updateSections() {
		self.sections = [nil]
		
		for service in self.peripheral.services {
			self.sections.append(service)
		}
		
		DispatchQueue.main.async {
			self.tableView.reloadData()
		}
	}
	
	@IBAction func toggleConnected() {
		if self.connectedSwitch.isOn {
			self.peripheral.connect()
		} else {
			self.peripheral.disconnect()
		}
	}
	

	
	
	//=============================================================================================
	//MARK: Tableview
	
	var sections: [BTLEService?] = []

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let service = self.sections[section] {
			return service.characteristics.count
		} else {
			return self.peripheral.advertisementData.count
		}
	}
	
	func numberOfSections(in tableView: UITableView) -> Int {
		return self.sections.count
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if let service = self.sections[indexPath.section] {
			let cell = tableView.dequeueReusableCell(withIdentifier: "characteristic", for: indexPath) as! CharacteristicTableViewCell
			let chr = service.characteristics[indexPath.row]
			
			cell.characteristic = chr
			
			return cell
 		} else {
			let cell = UITableViewCell(style: .value1, reuseIdentifier: "cell")
			var info = self.peripheral.advertisementData
			var keys = ((info as NSDictionary).allKeys as! [String]).sorted { $0 < $1 }
			let key = keys[indexPath.row]
			let value = info[key] as? CustomStringConvertible
			
			cell.textLabel?.text = key
			cell.detailTextLabel?.text = (value?.description ?? "").replacingOccurrences(of: "\n", with: "")
			
			return cell
		}
	}
	
	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		let label = UILabel(frame: CGRect(x: 0, y: 0, width: 320, height: 22))
		label.text = self.tableView(tableView, titleForHeaderInSection: section)
		label.backgroundColor = UIColor.orange
		label.textColor = UIColor.black
		
		return label
	}
	
	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if let service = self.sections[section] {
			return service.uuid.description
		} else {
			return "Advertisement Data"
		}
	}
	
	func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if indexPath.section == 0 { return 22 }
		
		return 100
	}
	
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if let service = self.sections[indexPath.section] {
			let chr = service.characteristics[indexPath.row]
			
			chr.reload()
			print("\(chr)")
		} else {
			var info = self.peripheral.advertisementData
			var keys = ((info as NSDictionary).allKeys as! [String]).sorted { $0 < $1 }
			let key = keys[indexPath.row]
			let value = info[key] as? CustomStringConvertible
			
			print("\(value)")
		}
	}
}
