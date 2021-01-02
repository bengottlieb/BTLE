//
//  PeripheralCellTableViewCell.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/19/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import BTLE
import Studio

class PeripheralCellTableViewCell: UITableViewCell {
	var peripheral: BTLEPeripheral? { didSet { self.setupNotificationsForPeripheral(peripheral: self.peripheral); self.updateUI() }}
	
	@IBOutlet var nameLabel: UILabel!
	@IBOutlet var detailsLabel: UILabel!
	@IBOutlet var rssiLabel: UILabel!
	@IBOutlet var connectedSwitch: UISwitch!
	
	
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
	
	@objc func updateUI() {
		DispatchQueue.main.async {
			if let per = self.peripheral {
                let name = per.iPhoneModelName ?? per.visibleName
				self.nameLabel.text = name + ", " + per.uuid.uuidString
				self.detailsLabel.text = per.summaryDescription
				self.rssiLabel.text = "\(per.rssi ?? 0)"
				
				let seconds = Int(abs(per.lastCommunicatedAt.timeIntervalSinceNow))
				var text = ""
				for (key, value) in per.advertisementData {
					if let describable = value as? CustomStringConvertible {
						let line = describable.description.replacingOccurrences(of: "\n", with: "")
						text += "\n\(key): \(line)"
					} else {
						text += "\n\(key): \(value)"
					}
					
				}
				
				let string = NSMutableAttributedString(string: "\(seconds) sec since last ping, \(per.services.count) services", attributes: [.font: UIFont.boldSystemFont(ofSize: 12)])
				string.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12)]))
				self.detailsLabel?.attributedText = string

				
				self.connectedSwitch.isOn = (per.state == .connected || per.state == .connecting)
				switch per.state {
				case .discovered:
					self.nameLabel.textColor = UIColor.darkGray
				case .connected:
					self.nameLabel.textColor = UIColor.black
				case .connecting:
					self.nameLabel.textColor = UIColor.orange
				case .disconnecting:
					self.nameLabel.textColor = UIColor.lightGray
				case .undiscovered:
					self.nameLabel.textColor = UIColor.red
				case .unknown:
					self.nameLabel.textColor = UIColor.yellow
				}
			}
		}
	}
	
	@IBAction func connect() {
		if self.connectedSwitch.isOn {
			self.peripheral?.connect(services: AppDelegate.servicesToRead)
		} else {
			self.peripheral?.disconnect()
		}
	}
	
	weak var updateTimer: Timer?
	@objc func queueUIUpdate() {
		self.updateTimer?.invalidate()
		DispatchQueue.main.async {
			self.updateTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(PeripheralCellTableViewCell.updateUI), userInfo: nil, repeats: false)
		}
	}
	
	func setupNotificationsForPeripheral(peripheral: BTLEPeripheral?) {
		self.removeAsObserver()
		if let per = peripheral {
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidDisconnect, selector: #selector(queueUIUpdate), object: per)
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidConnect, selector: #selector(queueUIUpdate), object: per)
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidUpdateRSSI, selector: #selector(queueUIUpdate), object: per)
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidBeginLoading, selector: #selector(queueUIUpdate), object: per)
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidFinishLoading, selector: #selector(queueUIUpdate), object: per)
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidUpdateName, selector: #selector(queueUIUpdate), object: per)
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidLoseComms, selector: #selector(queueUIUpdate), object: per)
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidRegainComms, selector: #selector(queueUIUpdate), object: per)
		}
	}
}
