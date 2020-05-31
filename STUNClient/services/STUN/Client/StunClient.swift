import NIO
import Foundation

public enum NatType {
    case noNat
    case blocked
    case fullCone
    case dymmetric
    case portRestricted
    case coneRestricted
}

public struct NatParams {
    let myExternalIP: String
    let myExternalPort: Int
    let natType: NatType
    public var description: String { return "External IP: \(myExternalIP) \n External Port: \(myExternalPort) \n NAT Type: \(natType) \n" }
}

public enum StunError: Error {
    case cantConvertValue
    case cantPreparePacket
    case cantRunUdpSocket(String)
    case cantResolveStunServerAddress
    case stunServerError(StunServerError)
    case cantRead(String)
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
    private var successCallback: ((String, Int) -> ())?
    private var natTypeCallback: ((NatParams) -> ())?
    private var errorCallback: ((StunError) -> ())?
    private var verboseCallback: ((String) -> ())?
    private var mode: ClientMode = .whoAmI
    
    private lazy var group = { MultiThreadedEventLoopGroup(numberOfThreads: 1) }()
    private lazy var bootstrap = {
        DatagramBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .channelInitializer { channel in
            channel.pipeline.addHandler(EnvelopToByteBufferConverter())
                .flatMap {
                    channel.pipeline.addHandler(ByteToMessageHandler(StunCodec()))
                }
                .flatMap {
                    channel.pipeline.addHandler(self.stunHandler!)
                }
        }
    }()
    
    private var stunHandler: StunTransportNioImpl?
    
    required public init(stunIpAddress: String, stunPort: UInt16, localPort: UInt16 = 0) {
        self.stunIpAddress = stunIpAddress
        self.stunPort = stunPort
        self.localPort = localPort == 0 ? UInt16.random(in: 10000..<55000) : localPort
    }
    
    deinit {
         try! group.syncShutdownGracefully()
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
    
    private func attributesHandler(_ attributes: [StunAttribute]) {
        attributes.forEach { attribute in
            verboseCallback?(attribute.description)
        }
        
        guard let attribute = attributes.filter({ $0.attributeType.getAttribute(from: Data(($0.attributeBodyData))) is GeneralAddressAttribute}).first,
            let addressPacket = attribute.attributeType.getAttribute(from: Data((attribute.attributeBodyData))) as? GeneralAddressAttribute else {
                errorCallback?(StunError.cantConvertValue)
                return
        }
        
        successCallback?(addressPacket.address, Int(addressPacket.port))
    }
    
    private func startWhoAmI() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            self.stunHandler = StunTransportNioImpl(errorHandler: self.errorCallback,
                                                    attributesHandler: self.attributesHandler)
            do {
                try self.startStunBindingProcedure().whenSuccess({ channel in
                    self.stunHandler?.sendBindingRequest(channel: channel, toStunServerAddress: self.stunIpAddress, toStunServerPort: Int(self.stunPort))
                    })
            } catch {
                self.errorCallback?(.cantRunUdpSocket((error as? NIO.IOError)?.description ?? error.localizedDescription))
            }
        }
    }
    
    private func startNatTypeDiscovery() {
        
    }
    
    private func startStunBindingProcedure() throws -> EventLoopFuture<Channel>  {
        return self.bootstrap.bind(host: "0.0.0.0", port: Int(self.localPort))
    }
}
