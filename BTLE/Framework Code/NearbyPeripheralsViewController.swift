//
//  NearbyPeripheralsViewController.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/26/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit

public class NearbyPeripheralsViewController: UIViewController {
	public override func loadView() {
		self.view = NearbyPeripheralsTableView(frame: CGRectZero)
		
		self.navigationItem.title = "Nearby Peripherals"
		self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Done, target: self, action: "dismiss")
	}
	
	func dismiss() {
		if let controller = self.navigationController {
			controller.dismissViewControllerAnimated(true, completion: nil)
		} else {
			self.dismissViewControllerAnimated(true, completion: nil)
		}
	}
}
