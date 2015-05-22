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
		var table = NearbyPeripheralsTableView(frame: CGRectZero)
		self.view = table
		table.parentViewController = self
		
		self.navigationItem.title = "Nearby Peripherals"
		self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Done, target: self, action: "dismiss")
		
		if BTLE.manager.services.count > 0 {
			self.navigationItem.titleView = self.filterToggle
			self.filterToggle.addTarget(self, action: "toggleFilter:", forControlEvents: .ValueChanged)
		}
	}
	
	public override func viewWillDisappear(animated: Bool) {
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
	
	func dismiss() {
		if let controller = self.navigationController {
			controller.dismissViewControllerAnimated(true, completion: nil)
		} else {
			self.dismissViewControllerAnimated(true, completion: nil)
		}
	}
	
	
	var filterToggle = UISwitch(frame: CGRectZero)
}
