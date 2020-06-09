![Swift](https://github.com/madmag77/STUNClient/workflows/Swift/badge.svg?branch=master)

# StunClient

Simple Stun client that connects to Stun server using UDP and asks for your external IP and Port. Can be used both from iOS and macOS.

## Requirements

- iOS 10.0+ / macOS 10.12+
- Xcode 11+
- Swift 5.2+

## Installation

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler.

Just add Stun Client to the `dependencies` of your `Package.swift` 

```swift
dependencies: [
    .package(url: "https://github.com/madmag77/STUNClient.git", .upToNextMajor(from: "1.0.2"))
]
```

or using Xcode Menu: File->Swift Packages->Add Package Dependency where just insert `https://github.com/madmag77/STUNClient.git` in the search line.


### Manually

In terminal:
```
git clone https://github.com/madmag77/STUNClient
cd STUNClient 
swift run
```

You should see the following output:
```
LOG: Start Who Am I procedure with Stun server 64.233.163.127:19302 from local port 14135
LOG: XOR_MAPPED_ADDRESS 
 Family: 1 
 Port: 54668  
 Address: xxx.xxx.xxx.xxx
COMPLETED, my address: xxx.xxx.xxx.xxx my port: 54668
```

Then you can try iOS example:
```
cd iOSExample 
open STUNClient.xcodeproj
```

Choose simulator and run the project.


## Usage

This is how Stun Client can be used (Google Stun IP address and port are being used here):

```swift
client = StunClient(stunIpAddress: "64.233.163.127", stunPort: 19302, localPort: UInt16(14135))
let successCallback: (String, Int) -> () = { [weak self] (myAddress: String, myPort: Int) in
        guard let self = self else { return }
        
        print("COMPLETED, my address: \(myAddress) my port: \(myPort)")
}
let errorCallback: (StunError) -> () = { [weak self] error in
            guard let self = self else { return }
            
            print("ERROR: \(error.localizedDescription)")
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
