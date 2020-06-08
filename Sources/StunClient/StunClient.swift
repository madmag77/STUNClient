import NIO
import Foundation

public enum NatType {
    case noNat
    case blocked
    case fullCone
    case symmetric
    case portRestricted
    case coneRestricted
}

public struct NatParams {
    let myExternalIP: String
    let myExternalPort: Int
    let natType: NatType
    public var description: String { return "External IP: \(myExternalIP) \n External Port: \(myExternalPort) \n NAT Type: \(natType) \n" }
}

public enum StunError: Error, Equatable {
    case cantConvertValue
    case cantPreparePacket
    case cantRunUdpSocket(String)
    case cantResolveStunServerAddress
    case stunServerError(StunServerError)
    case cantRead(String)
    case wrongResponse
    case readTimeout
    
    public var errorDescription: String {
        switch self {
        case .cantRunUdpSocket(let lowLevelError), .cantRead(let lowLevelError): return "\(self), \(lowLevelError)"
        case .stunServerError(let lowLevelError): return "\(self), \(lowLevelError)"
        default: return "\(self)"
        }
    }
}

fileprivate enum StunState {
    case initial
    case firstRequest
    case secondRequestWithAnotherPort
}

open class StunClient {
    private enum ClientMode {
        case whoAmI
        case natTypeDiscovery
    }
    
    private let stunIpAddress: String
    private let stunPort: UInt16
    private let localPort: UInt16
    private let timeoutInMilliseconds: Int64
    private var successCallback: ((String, Int) -> ())?
    private var natTypeCallback: ((NatParams) -> ())?
    private var errorCallback: ((StunError) -> ())?
    private var verboseCallback: ((String) -> ())?
    private var mode: ClientMode = .whoAmI
    
    private var group: MultiThreadedEventLoopGroup?
    private var bootstrap: DatagramBootstrap?
    
    private lazy var stunHandler = { StunInboundHandler(errorHandler: self.errorHandler,
                                                             attributesHandler: self.attributesHandler) }()

    private func initBootstrap() {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        bootstrap = DatagramBootstrap(group: group!)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .channelInitializer { channel in
            channel.pipeline.addHandlers([
                 EnvelopToByteBufferConverter(errorHandler: self.errorHandler),
                 ByteToMessageHandler(StunCodec()),
                 IdleStateHandler(readTimeout: TimeAmount.milliseconds(self.timeoutInMilliseconds)),
                 self.stunHandler
            ])
        }
    }
    
    private func closeBootstrap() {
        DispatchQueue.global().async {
            try! self.group?.syncShutdownGracefully()
        }
    }
    
    private func closeBootstrapSync() {
        try! self.group?.syncShutdownGracefully()
    }
    
    required public init(stunIpAddress: String, stunPort: UInt16, localPort: UInt16 = 0, timeoutInMilliseconds: Int64 = 100) {
        self.stunIpAddress = stunIpAddress
        self.stunPort = stunPort
        self.localPort = localPort == 0 ? UInt16.random(in: 10000..<55000) : localPort
        self.timeoutInMilliseconds = timeoutInMilliseconds
    }
    
    public func whoAmI() -> StunClient {
        mode = .whoAmI
        return self
    }
    
    public func discoverNatType() -> StunClient {
        mode = .natTypeDiscovery
        return self
    }
    
    public func ifWhoAmISuccessful(_ callback: @escaping (String, Int) -> ()) -> StunClient {
        guard successCallback == nil else { fatalError("successCallback can be assigned only once") }
        
        successCallback = callback
        return self
    }
    
    public func ifNatTypeSuccessful(_ callback: @escaping (NatParams) -> ()) -> StunClient {
        guard natTypeCallback == nil else { fatalError("natTypeCallback can be assigned only once") }
        
        natTypeCallback = callback
        return self
    }
    
    public func ifError(_ callback: @escaping (StunError) -> ()) -> StunClient {
        guard errorCallback == nil else { fatalError("errorCallback can be assigned only once") }
        
        errorCallback = callback
        return self
    }
    
    public func verbose(_ callback: @escaping (String) -> ()) -> StunClient {
        guard verboseCallback == nil else { fatalError("verboseCallback can be assigned only once") }
        
        verboseCallback = callback
        return self
    }
    
    public func start() {
        switch mode {
        case .whoAmI:
            startWhoAmI()
        case .natTypeDiscovery:
            startNatTypeDiscovery()
        }
    }
    
    private func errorHandler(_ error: StunError) {
        defer {
            closeBootstrap()
        }
        
        errorCallback?(error)
    }
    
    private func attributesHandler(_ attributes: [StunAttribute], responseWithError: Bool) {
        defer {
            closeBootstrap()
        }
        
        if let verboseCallback = verboseCallback {
            attributes.forEach { attribute in
                verboseCallback(attribute.description)
            }
        }
        
        if responseWithError {
            if let attribute = attributes.filter({ $0.attributeType == AttributeType.ERROR_CODE}).first,
                let errorPacket = attribute.attributeType.getAttribute(from: Data((attribute.attributeBodyData))) as? ERROR_CODE_ATTRIBUTE {
                errorCallback?(StunError.stunServerError(errorPacket.errorCode))
                return
            }
            errorCallback?(StunError.stunServerError(.unknown))
        }
        
        guard let attribute = attributes.filter({ $0.attributeType.getAttribute(from: Data(($0.attributeBodyData))) is GeneralAddressAttribute}).first,
            let addressPacket = attribute.attributeType.getAttribute(from: Data((attribute.attributeBodyData))) as? GeneralAddressAttribute else {
                errorCallback?(StunError.cantConvertValue)
                return
        }
        
        successCallback?(addressPacket.address, Int(addressPacket.port))
    }
    
    private func startWhoAmI() {
        verboseCallback?("Start Who Am I procedure with Stun server \(stunIpAddress):\(stunPort) from local port \(localPort)")
        
        closeBootstrapSync()
        
        initBootstrap()
        
        let _ = startStunBindingProcedure()!.always({ result in
                switch result {
                case .success(let channel):
                    self.stunHandler.sendBindingRequest(channel: channel, toStunServerAddress: self.stunIpAddress, toStunServerPort: Int(self.stunPort))
                case .failure(let error):
                    self.errorCallback?(.cantRunUdpSocket((error as? NIO.IOError)?.description ?? error.localizedDescription))
                }
            })
    }
    
    private func startNatTypeDiscovery() {
        // TODO
    }
    
    private func startStunBindingProcedure() -> EventLoopFuture<Channel>?  {
        return self.bootstrap?.bind(host: "0.0.0.0", port: Int(self.localPort))
    }
}
