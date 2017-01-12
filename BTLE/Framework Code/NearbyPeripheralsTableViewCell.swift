//
//  NearbyPeripheralsTableViewCell.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/24/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import Gulliver
import GulliverUI


public class NearbyPeripheralsTableViewCell: UITableViewCell {
	deinit {
		self.removeAsObserver()
		self.timer?.invalidate()
	}
	
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var rssiLabel: UILabel!
	@IBOutlet var lastCommunicatedAtLabel: UILabel!
	@IBOutlet var indicator: UIView!
	
	var timer: Timer?
	
	public var peripheral: BTLEPeripheral? { didSet {
		self.removeAsObserver()
		self.updateUI()
		if let per = self.peripheral {
			self.addAsObserver(for: BTLEManager.notifications.peripheralDidUpdateRSSI, selector: #selector(pinged), object: per)
		}
	}}
	
	func pinged() {
		DispatchQueue.main.async() {
			self.indicator.alpha = 1.0
			UIView.animate(withDuration: 0.5, animations: { self.indicator.alpha = 0.0} )
			self.updateUI()
		}
	}
	
	public func updateUI() {
		DispatchQueue.main.async() {
			if let per = self.peripheral {
				self.nameLabel.text = per.name
				self.rssiLabel.text = "\(per.rssi ?? 0)"
				
				self.rssiLabel.backgroundColor = per.state == .connected ? UIColor.blue : UIColor.clear
				self.rssiLabel.textColor = per.state == .connected ? UIColor.white : UIColor.black
				self.lastCommunicatedAtLabel.text = Date.ageString(age: abs(per.lastCommunicatedAt.timeIntervalSinceNow)) + ", " + per.distance.toString + " (\(per.uuid.uuidString)"
			}
		}
	}
	
	func updateLastCommsLabel() {
		if let per = self.peripheral {
			self.lastCommunicatedAtLabel.text = Date.ageString(age: abs(per.lastCommunicatedAt.timeIntervalSinceNow)) + ", " + per.distance.toString + " (\(per.uuid.uuidString)"
		}
	}
	
    public override func awakeFromNib() {
        super.awakeFromNib()
		
		DispatchQueue.main.async {
			self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(NearbyPeripheralsTableViewCell.updateLastCommsLabel), userInfo: nil, repeats: true)
		}
		
		self.rssiLabel.layer.borderWidth = 2.0
		self.rssiLabel.layer.borderColor = UIColor.black.cgColor
		self.rssiLabel.layer.masksToBounds = true
		
		self.rssiLabel.layer.cornerRadius = self.rssiLabel.bounds.size.width / 2
		
		self.indicator.backgroundColor = UIColor.blue
		self.indicator.layer.masksToBounds = true
		self.indicator.layer.cornerRadius = self.indicator.bounds.width / 2
		self.indicator.alpha = 0.0
		
	}
}

