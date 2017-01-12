//
//  NearbyPeripheralsViewController.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/26/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import CoreBluetooth

public class NearbyPeripheralsViewController: UIViewController {
	public override func loadView() {
		let table = NearbyPeripheralsTableView(frame: CGRect.zero)
		self.view = table
		table.parentViewController = self
		
		self.navigationItem.title = "Nearby Peripherals"
		self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissNearbyPeripherals))
		
		if BTLEManager.instance.serviceIDsToScanFor.count > 0 {
			self.navigationItem.titleView = self.filterToggle
			self.filterToggle.addTarget(self, action: #selector(toggleFilter), for: .valueChanged)
		}
	}
	
	public override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if self.appFilters.count > 0 {
			BTLEManager.scanner.turnOff()
			BTLEManager.instance.serviceIDsToScanFor = self.appFilters
			self.appFilters = []
			BTLEManager.scanner.startScanning()
		}
	}
	
	var appFilters: [CBUUID] = []
	func toggleFilter(toggle: UISwitch) {
		if BTLEManager.instance.serviceIDsToScanFor.count > 0 {
			BTLEManager.scanner.stopScanning()
			self.appFilters = BTLEManager.instance.serviceIDsToScanFor
			BTLEManager.instance.serviceIDsToScanFor = []
			BTLEManager.scanner.startScanning()
		} else {
			BTLEManager.scanner.stopScanning()
			BTLEManager.instance.serviceIDsToScanFor = self.appFilters
			self.appFilters = []
			BTLEManager.scanner.startScanning()
		}
	}
	
	func dismissNearbyPeripherals() {
		if let controller = self.navigationController {
			controller.dismiss(animated: true, completion: nil)
		} else {
			self.dismiss(animated: true, completion: nil)
		}
	}
	
	
	var filterToggle = UISwitch(frame: CGRect.zero)
}
