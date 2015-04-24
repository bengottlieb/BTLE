//
//  NearbyPeripheralsTableViewCell.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/24/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import SA_Swift


public class NearbyPeripheralsTableViewCell: UITableViewCell {
	deinit { self.removeAsObserver() }
	
	static let identifier = "NearbyPeripheralsTableViewCell"
	
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var rssiLabel: UILabel!
	
	public var peripheral: BTLEPeripheral? { didSet { self.updateUI() }}
	
	
	public func updateUI() {
		dispatch_async_main() {
			if let per = self.peripheral {
				self.nameLabel.text = per.name
				self.rssiLabel.text = "\(per.rssi ?? 0)"
				
				self.rssiLabel.backgroundColor = per.state == .Connected ? UIColor.blueColor() : UIColor.clearColor()
				self.rssiLabel.textColor = per.state == .Connected ? UIColor.whiteColor() : UIColor.blackColor()
			}
		}
	}
	
	
    public override func awakeFromNib() {
        super.awakeFromNib()
		
		self.rssiLabel.layer.borderWidth = 2.0
		self.rssiLabel.layer.borderColor = UIColor.blackColor().CGColor
		self.rssiLabel.layer.masksToBounds = true
		
		self.rssiLabel.layer.cornerRadius = self.rssiLabel.bounds.size.width / 2
		
		self.addAsObserver(BTLE.notifications.peripheralDidUpdateRSSI, selector: "updateUI")
	}
	
	
	
	
}
