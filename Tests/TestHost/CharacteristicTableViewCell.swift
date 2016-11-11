//
//  CharacteristicTableViewCell.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/21/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import BTLE
import Gulliver
import CoreBluetooth
import GulliverUI

class CharacteristicTableViewCell: UITableViewCell {
	@IBOutlet var nameAndPropertiesLabel: UILabel!
	@IBOutlet var stringValueLabel: UILabel!
	@IBOutlet var dataValueLabel: UILabel!
	@IBOutlet var notifySwitch: UISwitch!
	@IBOutlet var writeButton: UIButton!
	
	deinit {
		self.removeAsObserver()
	}
	
	var characteristic: BTLECharacteristic? { didSet {
			self.updateUI()
		}
	}
	
    override func awakeFromNib() {
        super.awakeFromNib()
		self.addAsObserver(for: BTLE.notifications.characteristicDidUpdate, selector: #selector(updateUI), object: nil)
		self.addAsObserver(for: BTLE.notifications.characteristicListeningChanged, selector: #selector(updateUI), object: nil)
		
		self.updateUI()
        // Initialization code
    }
	
	func updateUI() {
		btle_dispatch_main	{
			if let chr = self.characteristic {
				self.notifySwitch.isOn = (chr.state == .listening || chr.state == .startingToListen)
				self.notifySwitch.isEnabled = (chr.state == .listening || chr.state == .notListening)
				let desc = chr.cbCharacteristic.uuid.description
				self.nameAndPropertiesLabel?.text = desc.substring(to: desc.index(20)) + ": " + chr.propertiesAsString
				
				self.notifySwitch.isHidden = !chr.canNotify
				self.writeButton.isHidden = !chr.centralCanWriteTo
				
				if let data = chr.dataValue {
					self.stringValueLabel?.text = String(data: data as Data, encoding: .utf8) ?? ""
					self.dataValueLabel?.text = (data as Data).hexString
				} else {
					self.dataValueLabel?.text = ""
					self.stringValueLabel?.text = ""
				}
			}
		}
	}

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
	
	@IBAction func toggledNotify() {
		self.characteristic?.listenForUpdates() { state, chr in
			self.notifySwitch.isOn = chr.state == .listening
		}
	}
	
	@IBAction func writeTo() {
		let data = Data(hexString: "935343717a627a743074565a7849435876724867")!

		NSLog("%@", self.characteristic!.service!.fullDescription)
		
		self.characteristic?.writeBackValue(data: data) { chr, error in
			
		}
	}
}
