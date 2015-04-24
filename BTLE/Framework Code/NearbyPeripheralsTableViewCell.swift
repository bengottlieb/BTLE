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
	@IBOutlet var indicator: UIView!
	
	public var peripheral: BTLEPeripheral? { didSet {
		self.removeAsObserver()
		self.updateUI()
		if let per = self.peripheral {
			self.addAsObserver(BTLE.notifications.peripheralDidUpdateRSSI, selector: "pinged", object: per)
		}
	}}
	
	func pinged() {
		dispatch_async_main() {
			self.indicator.alpha = 1.0
			UIView.animateWithDuration(0.5, animations: { self.indicator.alpha = 0.0} )
			self.updateUI()
		}
	}
	
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
		
		self.indicator.backgroundColor = UIColor.blueColor()
		self.indicator.layer.masksToBounds = true
		self.indicator.layer.cornerRadius = self.indicator.bounds.width / 2
		self.indicator.alpha = 0.0
		
	}
	
	
	
	
}
