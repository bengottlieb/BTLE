//
//  BeaconSettingsViewController.swift
//  BTLE
//
//  Created by Ben Gottlieb on 10/11/15.
//  Copyright © 2015 Stand Alone, inc. All rights reserved.
//

import UIKit
import Gulliver
import CoreImage
import GulliverEXT

class BeaconSettingsViewController: UIViewController {
	
	@IBOutlet var uuidField: UITextField!
	@IBOutlet var majorField: UITextField!
	@IBOutlet var minorField: UITextField!
	@IBOutlet var enabledSwitch: UISwitch!
	@IBOutlet var imageView: UIImageView!

	class func presentInController(parent: UIViewController) {
		let controller = self.controller() as! BeaconSettingsViewController
		let nav = UINavigationController(rootViewController: controller)
		
		parent.presentViewController(nav, animated: true, completion: nil)
	}
	
	func done() {
		NSUserDefaults.set(self.uuidField.text, forKey: AppDelegate.beaconProximityIDKey)
		NSUserDefaults.set(self.majorField.text, forKey: AppDelegate.beaconMajorIDKey)
		NSUserDefaults.set(self.minorField.text, forKey: AppDelegate.beaconMinorIDKey)
		NSUserDefaults.set(self.enabledSwitch.on, forKey: AppDelegate.beaconEnabledKey)
		
		AppDelegate.instance.setupBeacon()
		self.dismiss()
	}
	
	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		
		self.updateQRCodeImage()
	}
	
	func updateQRCodeImage() {
		if let data = self.uuidField.text?.dataUsingEncoding(NSISOLatin1StringEncoding, allowLossyConversion: false), let filter = CIFilter(name: "CIQRCodeGenerator") {
			filter.setValue(data, forKey: "inputMessage")
			filter.setValue("Q", forKey: "inputCorrectionLevel")
			if let image = filter.outputImage {
				self.imageView.image = UIImage(CIImage: image)
			}
		}
	}
	
	weak var timer: NSTimer?
	override func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		self.timer?.invalidate()
		btle_dispatch_main {
			self.timer = NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: "updateQRCodeImage", userInfo: nil, repeats: false)
		}
		return true
	}
	
	override func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return false
	}
	
	
	func cancel() {
		self.dismiss()
	}
	
	func dismiss() {
		self.dismissViewControllerAnimated(true, completion: nil)
	}
	
	@IBAction func cycleUUID() {
		self.uuidField.text = NSUUID().UUIDString
		self.updateQRCodeImage()
	}
	
    override func viewDidLoad() {
        super.viewDidLoad()

		self.navigationItem.title = "iBeacon Settings"
		self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Cancel, target: self, action: "cancel")
		self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Done, target: self, action: "done")

		var label = NSUserDefaults.get(AppDelegate.beaconProximityIDKey) ?? ""
		if label.length == 0 { label = NSUUID().UUIDString }
		
		self.uuidField.text = label
		self.majorField.text = NSUserDefaults.get(AppDelegate.beaconMajorIDKey)
		self.minorField.text = NSUserDefaults.get(AppDelegate.beaconMinorIDKey)
		self.enabledSwitch.on = NSUserDefaults.get(AppDelegate.beaconEnabledKey) ?? false
		
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
