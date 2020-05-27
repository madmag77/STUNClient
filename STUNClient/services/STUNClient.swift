//
//  STUNClient.swift
//  STUNClient
//
//  Created by Artem Goncharov on 19/03/2017.
//  Copyright © 2017 MadMag. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

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
    case CantConvertValue
    case CantPreparePacket
    case CantBindToLocalPort(UInt16)
    case CantRunUdpSocket
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
    let msgRequestType: [UInt8] //2 bytes
    let bodyLength: [UInt8] //2 bytes
    let magicCookie: [UInt8] //4 bytes
    let transactionIdBindingRequest: [UInt8] //12 bytes
    let body: [UInt8] //attributes
    
    static func getBindingPacket(responseFromAddress: String = "", port: UInt16 = 0) -> STUNPacket  {
        
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
    
    func getPacketData() -> Data {
        return Data(msgRequestType + bodyLength + magicCookie + transactionIdBindingRequest + body)
    }
    
    static func getBindingAnswer(from answerPacket: Data) -> STUNPacket? {
        guard answerPacket.count >= 20 else { return nil }
        
        return STUNPacket(msgRequestType: [UInt8](answerPacket[0..<2]),
                                bodyLength:  [UInt8](answerPacket[2..<4]),
                                magicCookie: [UInt8](answerPacket[4..<8]),
                                transactionIdBindingRequest: [UInt8](answerPacket[8..<20]),
                                body: [UInt8](answerPacket[20..<answerPacket.count]))
    }
}

open class STUNClient: NSObject {
    fileprivate weak var delegate: STUNClientDelegate?
    fileprivate var stunAddress: String!
    fileprivate var stunPort: UInt16!
    fileprivate var updSocket: GCDAsyncUdpSocket?
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

extension STUNClient: GCDAsyncUdpSocketDelegate {
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
