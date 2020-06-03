# StunClient

Simple Stun client that connects to Stun server using UDP and asks for your external IP and Port. Can be used both from iOS and macOS.

There is another target CliSample where Stun client is used to print out your external IP and Port to the console. 

This is how Stun Client can be used (Google Stun IP address and port are being used here):

```swift
client = StunClient(stunIpAddress: "64.233.163.127", stunPort: 19302, localPort: UInt16(14135))
let successCallback: (String, Int) -> () = { [weak self] (myAddress: String, myPort: Int) in
        guard let self = self else { return }
        
        print("COMPLETED, my address: \(myAddress) my port: \(myPort)")
        self.semaphore.signal()
}
let errorCallback: (StunError) -> () = { [weak self] error in
            guard let self = self else { return }
            
            print("ERROR: \(error.localizedDescription)")
            self.semaphore.signal()
    }
let verboseCallback: (String) -> () = { [weak self] logText in
            guard let _ = self else { return }
            
            print("LOG: \(logText)")
    }

client
    .whoAmI()
    .ifWhoAmISuccessful(successCallback)
    .ifError(errorCallback)
    .verbose(verboseCallback)
    .start()
```
