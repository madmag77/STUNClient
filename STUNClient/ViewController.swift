//
//  ViewController.swift
//  STUNClient
//
//  Created by Artem Goncharov on 19/03/2017.
//  Copyright © 2017 MadMag. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var stunLog: UITextView!
    lazy var stunClient: STUNClient = STUNClient(delegate: self)
    var secondTime: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        stunLog.text = "-----==FIRST TIME==-----\n"
        stunClient.getNATParams(stunServer: "74.125.200.127", localPort: 14135, stunPort: 19302)
    }
}


//MARK: STUNClientDelegate
extension ViewController: STUNClientDelegate {
    func verbose(_ logText: String) {
        DispatchQueue.main.async {
            self.stunLog.text = self.stunLog.text + "\n" + logText
        }
    }
    
    func error(errorText: String) {
        DispatchQueue.main.async {
            self.stunLog.text = self.stunLog.text + "\n" + "ERROR: " + errorText
        }
    }
    
    func completed(nat: NATParams) {
        if secondTime {
            return
        }
        secondTime = true
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(500), execute: {
           // self.stunLog.text = "COMPLETED: " + "\n" + nat.description + "\n"
            self.stunLog.text = self.stunLog.text + "\n" + "-----==SECOND TIME==-----\n"
            self.stunClient.getNATParams(stunServer: "74.125.200.127", localPort: 14135, stunPort: 19302)
        })
    }
}
