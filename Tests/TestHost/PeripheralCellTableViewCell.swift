//
//  PeripheralCellTableViewCell.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/19/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import BTLE
import Gulliver
import GulliverEXT

class PeripheralCellTableViewCell: UITableViewCell {
	var peripheral: BTLEPeripheral? { didSet { self.setupNotificationsForPeripheral(self.peripheral); self.updateUI() }}
	
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var detailsLabel: UILabel!
	@IBOutlet var rssiLabel: UILabel!
	@IBOutlet var connectedSwitch: UISwitch!
	
	
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
	
	func updateUI() {
		dispatch_async_main {
			if let per = self.peripheral {
				self.nameLabel.text = per.name + ", " + per.uuid.UUIDString
				self.detailsLabel.text = per.summaryDescription
				self.rssiLabel.text = "\(per.rssi ?? 0)"
				
				let seconds = Int(abs(per.lastCommunicatedAt.timeIntervalSinceNow))
				var text = ""
				for (key, value) in per.advertisementData {
					if let describable = value as? CustomStringConvertible {
						let line = describable.description.stringByReplacingOccurrencesOfString("\n", withString: "")
						text += "\n\(key): \(line)"
					} else {
						text += "\n\(key): \(value)"
					}
					
				}
				
				let string = NSMutableAttributedString(string: "\(seconds) sec since last ping, \(per.services.count) services", attributes: [NSFontAttributeName: UIFont.boldSystemFontOfSize(12)])
				string.appendAttributedString(NSAttributedString(string: text, attributes: [NSFontAttributeName: UIFont.systemFontOfSize(12)]))
				self.detailsLabel?.attributedText = string

				
				self.connectedSwitch.on = (per.state == .Connected || per.state == .Connecting)
				switch per.state {
				case .Discovered:
					self.nameLabel.textColor = UIColor.darkGrayColor()
				case .Connected:
					self.nameLabel.textColor = UIColor.blackColor()
				case .Connecting:
					self.nameLabel.textColor = UIColor.orangeColor()
				case .Disconnecting:
					self.nameLabel.textColor = UIColor.lightGrayColor()
				case .Undiscovered:
					self.nameLabel.textColor = UIColor.redColor()
				case .Unknown:
					self.nameLabel.textColor = UIColor.yellowColor()
				}
			}
		}
	}
	
	@IBAction func connect() {
		if self.connectedSwitch.on {
			self.peripheral?.connect()
		} else {
			self.peripheral?.disconnect()
		}
	}
	
	weak var updateTimer: NSTimer?
	func queueUIUpdate() {
		self.updateTimer?.invalidate()
		self.updateTimer = NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: "updateUI", userInfo: nil, repeats: false)
	}
	
	func setupNotificationsForPeripheral(peripheral: BTLEPeripheral?) {
		self.removeAsObserver()
		if let per = peripheral {
			self.addAsObserver(BTLE.notifications.peripheralDidDisconnect, selector: "queueUIUpdate", object: per)
			self.addAsObserver(BTLE.notifications.peripheralDidConnect, selector: "queueUIUpdate", object: per)
			self.addAsObserver(BTLE.notifications.peripheralDidUpdateRSSI, selector: "queueUIUpdate", object: per)
			self.addAsObserver(BTLE.notifications.peripheralDidBeginLoading, selector: "queueUIUpdate", object: per)
			self.addAsObserver(BTLE.notifications.peripheralDidFinishLoading, selector: "queueUIUpdate", object: per)
			self.addAsObserver(BTLE.notifications.peripheralDidUpdateName, selector: "queueUIUpdate", object: per)
			self.addAsObserver(BTLE.notifications.peripheralDidLoseComms, selector: "queueUIUpdate", object: per)
			self.addAsObserver(BTLE.notifications.peripheralDidRegainComms, selector: "queueUIUpdate", object: per)
		}
	}
}
