import Foundation
import StunClient

public final class CliSample {
    private let arguments: [String]
    private let semaphore = DispatchSemaphore(value: 0)
    
    private lazy var client: StunClient = {
        let successCallback: (String, Int) -> () = { [weak self] (myAddress: String, myPort: Int) in
                guard let self = self else { return }
                
                print("COMPLETED, my address: \(myAddress) my port: \(myPort)")
                self.semaphore.signal()
        }
        let errorCallback: (StunError) -> () = { [weak self] error in
                    guard let self = self else { return }
                    
                    print("ERROR: \(error.errorDescription)")
                    self.semaphore.signal()
            }
        let verboseCallback: (String) -> () = { [weak self] logText in
                    guard let _ = self else { return }
                    
                    print("LOG: \(logText)")
            }

        return StunClient(stunIpAddress: "stun.l.google.com", stunPort: 19302, localPort: UInt16(14135))
            .whoAmI()
            .ifWhoAmISuccessful(successCallback)
            .ifError(errorCallback)
            .verbose(verboseCallback)
    } ()
    
    public init(arguments: [String] = CommandLine.arguments) {
        self.arguments = arguments
    }

    public func run() {
        client.start()
        
        _ = semaphore.wait(timeout: .distantFuture)
    }
}
