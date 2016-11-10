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
		
		if BTLE.manager.services.count > 0 {
			self.navigationItem.titleView = self.filterToggle
			self.filterToggle.addTarget(self, action: #selector(toggleFilter), for: .valueChanged)
		}
	}
	
	public override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if self.appFilters.count > 0 {
			BTLE.scanner.turnOff()
			BTLE.manager.services = self.appFilters
			self.appFilters = []
			BTLE.scanner.startScanning()
		}
	}
	
	var appFilters: [CBUUID] = []
	func toggleFilter(toggle: UISwitch) {
		if BTLE.manager.services.count > 0 {
			BTLE.scanner.stopScanning()
			self.appFilters = BTLE.manager.services
			BTLE.manager.services = []
			BTLE.scanner.startScanning()
		} else {
			BTLE.scanner.stopScanning()
			BTLE.manager.services = self.appFilters
			self.appFilters = []
			BTLE.scanner.startScanning()
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
