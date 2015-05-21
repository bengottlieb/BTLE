//
//  NearbyPeripheralsTableView.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/24/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import UIKit
import SA_Swift

public class NearbyPeripheralsTableView: UITableView, UITableViewDelegate, UITableViewDataSource {
	deinit { self.removeAsObserver() }

	public required init(coder aDecoder: NSCoder) { super.init(coder: aDecoder); self.setup() }
	public override init(frame: CGRect) { super.init(frame: frame); self.setup() }
	public override init(frame: CGRect, style: UITableViewStyle) { super.init(frame: frame, style: style); self.setup() }
	
	public var peripherals: [BTLEPeripheral]? { didSet { self.reload() }}
	
	public func reload() { dispatch_async_main() { self.reloadData() }}
	
	var parentViewController: UIViewController?
	
	//=============================================================================================
	//MARK: Private
	var actualPeripherals: [BTLEPeripheral] { return self.peripherals ?? self.nearbyPeripherals }
	var nearbyPeripherals: [BTLEPeripheral] = []
	
	func setup() {
		self.nearbyPeripherals = Array(BTLE.manager.scanner.peripherals)
		self.delegate = self
		self.dataSource = self
		
		self.addAsObserver(BTLE.notifications.peripheralWasDiscovered, selector: "reloadNearbyPeripherals", object: nil)
		
		self.registerNib(UINib(nibName: "NearbyPeripheralsTableViewCell", bundle: NSBundle(forClass: self.dynamicType)), forCellReuseIdentifier: NearbyPeripheralsTableViewCell.identifier)
	}
	
	//=============================================================================================
	//MARK: Notifications
	public func reloadNearbyPeripherals() {
		self.nearbyPeripherals = Array(BTLE.manager.scanner.peripherals)
		self.reload()
	}

	
	//=============================================================================================
	//MARK: Tableview delegate/datasource
	public func numberOfSectionsInTableView(tableView: UITableView) -> Int { return 1 }
	public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return self.actualPeripherals.count }
	
	public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		if let cell = tableView.dequeueReusableCellWithIdentifier(NearbyPeripheralsTableViewCell.identifier, forIndexPath: indexPath) as? NearbyPeripheralsTableViewCell {
			cell.peripheral = self.actualPeripherals[indexPath.row]
			
			return cell
		}
		return UITableViewCell()
	}
	
	public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		var per = self.actualPeripherals[indexPath.row]
		var advertisingInfo = per.advertisementData
		var text = advertisingInfo.description
		var alert = UIAlertController(title: nil, message: text, preferredStyle: .Alert)
		alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: { action in
			alert.dismissViewControllerAnimated(true, completion: nil)
		}))
		self.parentViewController?.presentViewController(alert, animated: true, completion: nil)
		
		
		
	}
}

