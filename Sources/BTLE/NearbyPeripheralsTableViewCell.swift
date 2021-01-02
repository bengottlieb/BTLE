//
//  NearbyPeripheralsTableViewCell.swift
//  BTLE
//
//  Created by Ben Gottlieb on 4/24/15.
//  Copyright (c) 2015 Stand Alone, inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import Studio


public class NearbyPeripheralsTableViewCell: UITableViewCell {
	deinit {
		self.removeAsObserver()
		self.timer?.invalidate()
	}
	
	let nameLabel = UILabel()
		.font(.systemFont(ofSize: 17))
		.translatesAutoresizingMaskIntoConstraints(false)
		.lineBreakMode(.byTruncatingMiddle)
		.contentCompressionResistancePriority(.defaultLow, for: .horizontal)

	let rssiLabel = UILabel()
		.font(.systemFont(ofSize: 19))
		.translatesAutoresizingMaskIntoConstraints(false)

	let lastCommunicatedAtLabel = UILabel()
		.font(.systemFont(ofSize: 13))
		.textColor(.gray)
		.lineBreakMode(.byTruncatingMiddle)
		.contentCompressionResistancePriority(.defaultLow, for: .horizontal)
		.translatesAutoresizingMaskIntoConstraints(false)

	let indicator = UIView()
		.translatesAutoresizingMaskIntoConstraints(false)

	var timer: Timer?
	
	public var peripheral: BTLEPeripheral? { didSet {
		self.removeAsObserver()
		self.updateUI()
		if let per = self.peripheral {
			self.addAsObserver(of: BTLEManager.Notifications.peripheralDidUpdateRSSI, selector: #selector(pinged), object: per)
		}
	}}
	
	@objc func pinged() {
		DispatchQueue.main.async() {
			self.indicator.alpha = 1.0
			UIView.animate(withDuration: 0.5, animations: { self.indicator.alpha = 0.0} )
			self.updateUI()
		}
	}
	
	public func updateUI() {
		if self.nameLabel.superview == nil {
			contentView.addSubview(nameLabel)
			contentView.addSubview(rssiLabel)
			contentView.addSubview(lastCommunicatedAtLabel)
			contentView.addSubview(indicator)
			
			NSLayoutConstraint.activate([
				nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
				nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
				nameLabel.heightAnchor.constraint(equalToConstant: 21),

				rssiLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 10),
				rssiLabel.leadingAnchor.constraint(equalTo: lastCommunicatedAtLabel.trailingAnchor, constant: 10),
				rssiLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 6),
				rssiLabel.heightAnchor.constraint(equalToConstant: 36),
				rssiLabel.widthAnchor.constraint(equalToConstant: 36),
				
				indicator.topAnchor.constraint(equalTo: contentView.topAnchor),
				indicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
				indicator.heightAnchor.constraint(equalToConstant: 12),
				indicator.widthAnchor.constraint(equalToConstant: 12),
				
				lastCommunicatedAtLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
				lastCommunicatedAtLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
				lastCommunicatedAtLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
				lastCommunicatedAtLabel.heightAnchor.constraint(equalToConstant: 21),
			])
			
			let trailing = rssiLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5)
			trailing.priority = .defaultHigh
			trailing.isActive = true
		}
		
		
		if let per = self.peripheral {
			self.nameLabel.text = per.name
			self.rssiLabel.text = "\(per.rssi ?? 0)"
			
			self.rssiLabel.backgroundColor = per.state == .connected ? UIColor.blue : UIColor.clear
			self.rssiLabel.textColor = per.state == .connected ? UIColor.white : UIColor.black
			self.lastCommunicatedAtLabel.text = Date.ageString(age: abs(per.lastCommunicatedAt.timeIntervalSinceNow)) + ", " + per.distance.toString + " (\(per.uuid.uuidString)"
		}
	}
	
	@objc func updateLastCommsLabel() {
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

#endif
