//
//  STUNClient.swift
//  STUNClient
//
//  Created by Artem Goncharov on 19/03/2017.
//  Copyright © 2017 MadMag. All rights reserved.
//

import UIKit
import CocoaAsyncSocket
import NIO

public protocol STUNClientDelegate: class {
    func verbose(_ logText: String)
    func error(errorText: String)
    func completed(nat: NATParams)
}

public enum NATType {
    case NoNAT
    case Blocked
    case FullCone
    case Symmetric
    case PortRestricted
    case ConeRestricted
}

public struct NATParams {
    let myExternalIP: String
    let myExternalPort: Int
    let natType: NATType
    public var description: String { return "External IP: \(myExternalIP) \n External Port: \(myExternalPort) \n NAT Type: \(natType) \n" }
}

public enum STUNError: Error {
    case cantConvertValue
    case cantPreparePacket
    case cantRunUdpSocket
}

public enum STUNServerError: UInt16 {
    case BadRequest = 400
    case Unauthorized = 401
    case UnknownAttribute = 420
    case StaleCredentials = 430
    case IntegrityCheckFailure = 431
    case MissingUsername = 432
    case UseTLS = 433
    case ServerError = 500
    case GlobalFailure = 600
}

fileprivate enum STUNState {
    case Init
    case FirstRequest
    case SecondRequestWithAnotherPort
}

let RandomLocalPort: UInt16 = 0
let STUNRequestTimeout: TimeInterval = 3.0
let MagicCookie: [UInt8] = [0x21, 0x12, 0xA4, 0x42]

enum PacketsTags: Int {
    case BindingRequest = 1
}

struct RandomTransactionID {
    static func getTransactionID() -> Array<UInt8> {
        var transactionID: Array = Array<UInt8>()
        for _ in 0...11 {
            transactionID.append(UInt8(arc4random_uniform(UInt32(UInt8.max))))
        }
        return transactionID
    }
}

enum MessageType: UInt16 {
    case BindingRequest = 0x0001
    case BindingResponse = 0x0101
    case BindingErrorResponse = 0x0111
    case SharedSecretRequest = 0x0002
    case SharedSecretResponse = 0x0102
    case SharedSecretErrorResponse = 0x0112
}

struct STUNPacket {
    private static let stunHeaderLength: UInt16 = 20
    private let msgRequestType: [UInt8] //2 bytes
    private let bodyLength: [UInt8] //2 bytes
    private let magicCookie: [UInt8] //4 bytes
    private let transactionIdBindingRequest: [UInt8] //12 bytes
    private let body: [UInt8] //attributes
    
    func getPacketData() -> Data {
        return Data(msgRequestType + bodyLength + magicCookie + transactionIdBindingRequest + body)
    }
    
    static func getBindingRequest(responseFromAddress: String = "", port: UInt16 = 0) -> STUNPacket  {
        
        let body: [UInt8] = responseFromAddress == "" ? []: getChangeRequestAttribute() + getResponseAddressAttribute(responseFromAddress: responseFromAddress, port: port)
        
        return STUNPacket(msgRequestType: [0x00, 0x01],
                                bodyLength:  [UInt8(body.count / 256), UInt8(body.count % 256)],
                                magicCookie: MagicCookie,
                                transactionIdBindingRequest: RandomTransactionID.getTransactionID(),
                                body: body
        )
    }
    
    static func getChangeRequestAttribute() ->  [UInt8] {
        let attributeChangeRequest: [UInt8] = [0x00, 0x00, 0x00, 0x02]
        return STUNAttribute.formAttribute(type: .CHANGE_REQUEST,
                                    body: attributeChangeRequest).toArray()
    }
    
    static func getResponseAddressAttribute(responseFromAddress: String, port: UInt16) ->  [UInt8] {
        return STUNAttribute.formAttribute(type: .RESPONSE_ADDRESS,
                                           body: NORMAL_ADDRESS_ATTRIBUTE_PACKET.formPacket(with: responseFromAddress, and: port).getPacketData()).toArray()
    }
    
    static func parse(from data: Data) -> STUNPacket? {
        guard data.count >= stunHeaderLength, data.count == Int(data[2])*256 + Int(data[3]) + 20 else {
            return nil
        }
        
        return STUNPacket(msgRequestType: [UInt8](data[0..<2]),
                                bodyLength:  [UInt8](data[2..<4]),
                                magicCookie: [UInt8](data[4..<8]),
                                transactionIdBindingRequest: [UInt8](data[8..<20]),
                                body: [UInt8](data[20..<data.count]))
    }
    
    static func parse(from data: UnsafeRawBufferPointer) -> STUNPacket? {
        guard data.count >= stunHeaderLength, data.count == Int(data[2])*256 + Int(data[3]) + 20 else {
            return nil
        }
        
        return STUNPacket(msgRequestType: [UInt8](data[0..<2]),
                                bodyLength:  [UInt8](data[2..<4]),
                                magicCookie: [UInt8](data[4..<8]),
                                transactionIdBindingRequest: [UInt8](data[8..<20]),
                                body: [UInt8](data[20..<data.count]))
    }
}

protocol StunTransport {
    
}



final class StunCodec: ByteToMessageDecoder {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = STUNPacket
        
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let packet = buffer.withUnsafeReadableBytes({pointer in STUNPacket.parse(from: pointer)}) else {
             return .needMoreData
        }
        
        buffer.moveReaderIndex(to: packet.getPacketData().count)
        
        context.fireChannelRead(self.wrapInboundOut(packet))
        
        return .continue
    }
}

private final class EnvelopToByteBufferConverter: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias InboundOut = ByteBuffer
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        let byteBuffer = envelope.data
        context.fireChannelRead(self.wrapInboundOut(byteBuffer))
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[EnvelopToByteBufferConverter] error: ", error)
        context.close(promise: nil)
    }
}

private final class StunTransportNioImpl: ChannelInboundHandler {
    public typealias InboundIn = STUNPacket
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    
    public func sendBindingRequest(channel: Channel, toStunServerAddress address: String, toStunServerPort port: Int) {
        let requestData = STUNPacket.getBindingRequest().getPacketData()
        
        do {
            let remoteAddress = try SocketAddress.makeAddressResolvingHost(address, port: port)
            
            var buffer = channel.allocator.buffer(capacity: requestData.count)
            buffer.writeBytes(requestData)

            let envolope = AddressedEnvelope<ByteBuffer>(remoteAddress: remoteAddress, data: buffer)
            
            channel.writeAndFlush(self.wrapOutboundOut(envolope), promise: nil)
        } catch {
            print("error: ", error)
        }
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let packet = self.unwrapInboundIn(data)
        
        let string = String(describing: packet)
        print("Received: '\(string)' back from the server, closing channel.")
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        context.close(promise: nil)
    }
}

extension StunTransportNioImpl: StunTransport {
    
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
    private var natTypeCallback: ((NATParams) -> ())?
    private var errorCallback: ((STUNError) -> ())?
    private var verboseCallback: ((String) -> ())?
    private var mode: ClientMode = .whoAmI
    
    private lazy var group = { MultiThreadedEventLoopGroup(numberOfThreads: 1) }()
    private lazy var bootstrap = {
        DatagramBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .channelInitializer { channel in
            channel.pipeline.addHandler(EnvelopToByteBufferConverter()).flatMap { v in
                channel.pipeline.addHandler(ByteToMessageHandler(StunCodec())).flatMap { v in
                    channel.pipeline.addHandler(self.stunHandler)
                }
            }
        }
    }()
    
    private lazy var stunHandler: StunTransportNioImpl = {
       StunTransportNioImpl()
    }()
    
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
    
    public func ifNatTypeSuccessful(_ callback: @escaping (NATParams) -> ()) -> StunClient {
        guard natTypeCallback == nil else { fatalError("natTypeCallback can be assigned only once") }
        
        natTypeCallback = callback
        return self
    }
    
    public func ifError(_ callback: @escaping (STUNError) -> ()) -> StunClient {
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
    
    private func startWhoAmI() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            do {
                try self.startStunBindingProcedure().whenSuccess({ channel in
                    self.stunHandler.sendBindingRequest(channel: channel, toStunServerAddress: self.stunIpAddress, toStunServerPort: Int(self.stunPort))
                    })
            } catch {
                print((error as? NIO.IOError)?.description ?? error.localizedDescription)
                self.errorCallback?(.cantRunUdpSocket)
            }
        }
    }
    
    private func startNatTypeDiscovery() {
        
    }
    
    private func startStunBindingProcedure() throws -> EventLoopFuture<Channel>  {
        return self.bootstrap.bind(host: "0.0.0.0", port: Int(self.localPort))
    }
}
/*
public struct STUNClient {
    fileprivate weak var delegate: STUNClientDelegate?
    fileprivate var stunAddress: String!
    fileprivate var stunPort: UInt16!

    fileprivate lazy var asyncQueue: DispatchQueue = {
        return DispatchQueue(label: "STUNClient")
    }()

    fileprivate var bindingPacket: STUNPacket!
    fileprivate var state: STUNState = .Init
    fileprivate var attributesFromEmptyRequestFunc: (([STUNAttribute]) -> ())?
    
    
    required public init(delegate: STUNClientDelegate?) {
        super.init()
        self.delegate = delegate
    }
    
    func getNATParams(stunAddress: String, localPort: UInt16 = RandomLocalPort, stunPort: UInt16 = 3478)  throws {
        
        delegate?.verbose("Initializing...")
        self.stunAddress = stunAddress
        self.stunPort = stunPort
        
        closeSocket()
        createSocket()
        
        try self.bindSocketTo(localPort)
        try self.startReceiving()
        
        state = .FirstRequest
        
        getAttributesFromEmptyBindingRequet({_ in })
    }

    func getAttributesFromEmptyBindingRequet(_ callBack:@escaping ([STUNAttribute]) -> ()) {
        attributesFromEmptyRequestFunc = callBack
        bindingPacket = prepareEmptyBindingRequest()
        sendData(bindingPacket.getPacketData())
        
        callBack([])
    }

    func bindSocketTo(_ localPort: UInt16) throws {
        if localPort != RandomLocalPort {
            do {
                try updSocket?.bind(toPort: localPort)
            } catch {
                updSocket = nil
                throw STUNError.CantBindToLocalPort(localPort)
            }
        }
    }
    
    func startReceiving() throws {
        guard let updSocket = updSocket else { throw STUNError.CantRunUdpSocket }
        do {
            try updSocket.beginReceiving()
        } catch {
            self.updSocket = nil
            throw STUNError.CantRunUdpSocket
        }
    }

    
    func prepareEmptyBindingRequest() -> STUNPacket {
        delegate?.verbose("Prepare empty binding packet to sent")

        return STUNPacket.getBindingPacket()
    }
    
    func prepareBindingRequestChangePort(to port: UInt16 = 3478) -> STUNPacket {
        delegate?.verbose("Prepare change port to \(port) binding packet to sent")
        
        return STUNPacket.getBindingPacket(responseFromAddress: stunAddress, port: port)
    }
    
    func sendData(_ data: Data) {
        delegate?.verbose("Sending binding packet...")
        
        updSocket?.send(data, toHost: stunAddress, port: stunPort, withTimeout: 3.0, tag: PacketsTags.BindingRequest.rawValue)
    }
    
    func closeSocket() {
        if updSocket != nil {
            updSocket?.close()
        }
    }
    
    func createSocket() {
        updSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue:  asyncQueue)
    }
    
    func getReceivedPacket(from data: Data) -> STUNPacket? {
        guard let receivedPacket: STUNPacket = STUNPacket.getBindingAnswer(from: data) else {
            return nil
        }
        
        guard receivedPacket.magicCookie == (bindingPacket?.magicCookie)!, receivedPacket.transactionIdBindingRequest == (bindingPacket?.transactionIdBindingRequest)!  else {
            delegate?.error(errorText: "Received data from another request")
            return nil
        }
        
        delegate?.verbose("Receive packet \(MessageType(rawValue: UInt16(receivedPacket.msgRequestType[0]) * 256 + UInt16(receivedPacket.msgRequestType[1])))")
        
        //get responss body length
        let responseBodyLength: Int = Int(receivedPacket.bodyLength[0]) * 256 + Int(receivedPacket.bodyLength[1])
        
        delegate?.verbose("Received data body has length: \(responseBodyLength)")
        
        guard responseBodyLength == receivedPacket.body.count else {
            delegate?.error(errorText: "Received data has unproper body length")
            return nil
        }
        
        return receivedPacket
    }
    
    func getAttributes(from receivedPacket: STUNPacket) -> [STUNAttribute] {
        var attributes: [STUNAttribute] = []
        var body: Array<UInt8> = receivedPacket.body
        while true {
            do {
                let attribute: STUNAttribute = try STUNAttribute.getAttribute(from: body)
                body.removeFirst(attribute.getAttributeLength())
                attributes.append(attribute)
                try delegate?.verbose("\(attribute.description()) \n")
                if body.count < 4 || attribute.getAttributeType() == .ERROR_CODE {
                    break
                }
            } catch  {
                delegate?.error(errorText: "Error in response parsing")
                return []
            }
        }
        return attributes
    }
}

extension STUNClient: ChannelInboundHandler {
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didSendDataWithTag tag: Int) {
        delegate?.verbose("Sended binding packet sucessfully")
    }
 
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didNotSendDataWithTag tag: Int, dueToError error: Error?) {
        delegate?.error(errorText: "Can't send data")
    }
    
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        
        delegate?.verbose("Received data from STUN server with address: \(address[4]).\(address[5]).\(address[6]).\(address[7]) port: \(UInt16(address[2]) * 256 + UInt16(address[3]))")

        if data.count < 20 {
            delegate?.error(errorText: "Received data length too short")
            return;
        }
        
        guard let receivedPacket = getReceivedPacket(from: data) else {
            return
        }
        
        let _ = getAttributes(from: receivedPacket)

        switch self.state {
        case .FirstRequest:
            bindingPacket = prepareBindingRequestChangePort(to: 50000)
            sendData(bindingPacket.getPacketData())
            state = .SecondRequestWithAnotherPort
            break
            
        case .SecondRequestWithAnotherPort:
            updSocket?.close()
            delegate?.completed(nat: NATParams(myExternalIP: "", myExternalPort: 2, natType: .FullCone))
            break
            
        default:
            break
        }
    }
    
    public func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        delegate?.verbose("Socket has been closed")
    }
}
*/
