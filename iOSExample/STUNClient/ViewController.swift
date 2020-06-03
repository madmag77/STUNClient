import UIKit
import StunClient

class ViewController: UIViewController {
    @IBOutlet weak var stunLog: UITextView!
    var secondTime: Bool = false
    var client: StunClient!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.stunLog.text = ""
        let localPort = 14135
        client = StunClient(stunIpAddress: "64.233.163.127", stunPort: 19302, localPort: UInt16(localPort))
        let successCallback: (String, Int) -> () = { [weak self] (myAddress: String, myPort: Int) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.stunLog.text = self.stunLog.text + "\n\n" + "COMPLETED, my address: " + myAddress + " my port: " + String(myPort)
            }
        }
        let errorCallback: (StunError) -> () = { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.stunLog.text = self.stunLog.text + "\n" + "ERROR: " + error.localizedDescription
                }
            }
        let verboseCallback: (String) -> () = { [weak self] logText in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.stunLog.text = self.stunLog.text + "\n" + logText
                }
            }
        
        
        client
            .whoAmI()
            .ifWhoAmISuccessful(successCallback)
            .ifError(errorCallback)
            .verbose(verboseCallback)
            .start()
    }
}
