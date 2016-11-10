//
//  NearbyPeripheralsTableView.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/24/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import Foundation
import UIKit
import Gulliver
import GulliverUI

public class NearbyPeripheralsTableView: UITableView, UITableViewDelegate, UITableViewDataSource {
	deinit { self.removeAsObserver() }

	public required init?(coder aDecoder: NSCoder) { super.init(coder: aDecoder); self.setup() }
	public init(frame: CGRect) { super.init(frame: frame, style: .plain); self.setup() }
	public override init(frame: CGRect, style: UITableViewStyle) { super.init(frame: frame, style: style); self.setup() }
	
	public var peripherals: [BTLEPeripheral]? { didSet { self.reload() }}
	
	public func reload() { DispatchQueue.main.async() { self.reloadData() }}
	
	var parentViewController: UIViewController?
	
	//=============================================================================================
	//MARK: Private
	var actualPeripherals: [BTLEPeripheral] { return self.peripherals ?? self.nearbyPeripherals }
	var nearbyPeripherals: [BTLEPeripheral] = []
	
	func setup() {
		self.nearbyPeripherals = Array(BTLE.scanner.peripherals)
		self.delegate = self
		self.dataSource = self
		
		self.addAsObserver(for: BTLE.notifications.peripheralWasDiscovered, selector: #selector(NearbyPeripheralsTableView.reloadNearbyPeripherals), object: nil)
		
		self.register(UINib(nibName: "NearbyPeripheralsTableViewCell", bundle: Bundle(for: type(of: self))), forCellReuseIdentifier: NearbyPeripheralsTableViewCell.identifier)
	}
	
	//=============================================================================================
	//MARK: Notifications
	public func reloadNearbyPeripherals() {
		self.nearbyPeripherals = Array(BTLE.scanner.peripherals)
		self.reload()
	}

	
	//=============================================================================================
	//MARK: Tableview delegate/datasource
	public func numberOfSections(in tableView: UITableView) -> Int { return 1 }
	public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return self.actualPeripherals.count }
	
	public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if let cell = tableView.dequeueReusableCell(withIdentifier: NearbyPeripheralsTableViewCell.identifier, for: indexPath) as? NearbyPeripheralsTableViewCell {
			cell.peripheral = self.actualPeripherals[indexPath.row]
			
			return cell
		}
		return UITableViewCell()
	}
	
	public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let per = self.actualPeripherals[indexPath.row]
		let advertisingInfo = per.advertisementData
		let text = advertisingInfo.description
		let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
			alert.dismiss(animated: true, completion: nil)
		}))
		self.parentViewController?.present(alert, animated: true, completion: nil)
		
		
		
	}
}

