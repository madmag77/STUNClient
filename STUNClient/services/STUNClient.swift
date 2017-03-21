//
//  STUNClient.swift
//  STUNClient
//
//  Created by Artem Goncharov on 19/03/2017.
//  Copyright © 2017 MadMag. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

let RandomLocalPort: UInt16 = 0
let STUNRequestTimeout: TimeInterval = 3.0

enum PacketsTags: Int {
    case BindingRequest = 1
}

enum AddressType {
    case MappedAddress
    case XorMappedAddress
}

enum ResponseType {
    case BindingResponse
    case BindingErrorResponse
}

enum AttributeType: Int {
    case MAPPED_ADDRESS = 0x0001
    case RESPONSE_ADDRESS =  0x0002
    case CHANGE_REQUEST = 0x0003
    case SOURCE_ADDRESS = 0x0004
    case CHANGED_ADDRESS = 0x0005
    case USERNAME = 0x0006
    case PASSWORD = 0x0007
    case MESSAGE_INTEGRITY = 0x0008
    case ERROR_CODE = 0x0009
    case UNKNOWN_ATTRIBUTES = 0x000a
    case REFLECTED_FROM = 0x000b
    case CHANNEL_NUMBER =	0x000C
    case LIFETIME =	0x000D
    case BANDWIDTH = 	0x0010
    case XOR_PEER_ADDRESS =	0x0012
    case DATA =	0x0013
    case REALM =	0x0014
    case NONCE =	0x0015
    case XOR_RELAYED_ADDRESS =	0x0016
    case REQUESTED_ADDRESS_FAMILY =	0x0017
    case EVEN_PORT =	0x0018
    case REQUESTED_TRANSPORT =	0x0019
    case DONT_FRAGMENT =	0x001A
    case XOR_MAPPED_ADDRESS =	0x0020
    case TIMER_VAL =	0x0021
    case RESERVATION_TOKEN =	0x0022
    case USE_CANDIDATE =	0x0025
    case PADDING =	0x0026
    case RESPONSE_PORT =	0x0027
    case CONNECTION_ID =	0x002A
    case SOFTWARE =	0x8022
    case ALTERNATE_SERVER =	0x8023
    case FINGERPRINT =	0x8028
    case ICE_CONTROLLED =	0x8029
    case ICE_CONTROLLING =	0x802A
    case RESPONSE_ORIGIN =	0x802B
    case OTHER_ADDRESS =	0x802C
    case UNKNOWN = 0
}

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
    case Restricted
}

public struct NATParams {
    let myExternalIP: String
    let myExternalPort: Int
    let natType: NATType
    public var description: String { return "External IP: \(myExternalIP) \n External Port: \(myExternalPort) \n NAT Type: \(natType) \n" }
}

struct STUNAttribute {
    let attributeType: Array<UInt8> //2 bytes
    let attributeLength: Array<UInt8> //2 bytes
    let attributeBody: Array<UInt8> //?? bytes

    static func getAttribute(from data: Array<UInt8>) -> STUNAttribute {
        return STUNAttribute(attributeType: [UInt8](data[0..<2]),
                             attributeLength:  [UInt8](data[2..<4]),
                             attributeBody: [UInt8](data[4..<4 + Int(data[2]) * 256 + Int(data[3])]))
    }
    
    func getAttributeLength() -> Int {
        return attributeType.count + attributeLength.count + attributeBody.count
    }
    
    func getAttributeType() -> AttributeType {
        return AttributeType(rawValue: Int(self.attributeType[0]) * 256 + Int(self.attributeType[1])) ?? .UNKNOWN
    }
    
    func getIPAddress() -> String {
        switch getAttributeType() {
        case .MAPPED_ADDRESS:
            return "\(attributeBody[4]).\(attributeBody[5]).\(attributeBody[6]).\(attributeBody[7])"
        case .RESPONSE_ADDRESS:
            return "\(attributeBody[4]).\(attributeBody[5]).\(attributeBody[6]).\(attributeBody[7])"
        case .RESPONSE_ORIGIN:
            return "\(attributeBody[4]).\(attributeBody[5]).\(attributeBody[6]).\(attributeBody[7])"
        case .OTHER_ADDRESS:
            return "\(attributeBody[4]).\(attributeBody[5]).\(attributeBody[6]).\(attributeBody[7])"
        default:
            return ""
        }
    }
    
    func getPort() -> Int {
        switch getAttributeType() {
        case .MAPPED_ADDRESS:
            return Int(attributeBody[2]) * 256 + Int(attributeBody[3])
        case .RESPONSE_ADDRESS:
            return Int(attributeBody[2]) * 256 + Int(attributeBody[3])
        case .RESPONSE_ORIGIN:
            return Int(attributeBody[2]) * 256 + Int(attributeBody[3])
        case .OTHER_ADDRESS:
            return Int(attributeBody[2]) * 256 + Int(attributeBody[3])
        default:
            return 0
        }
    }

    func description() -> String {
        switch getAttributeType() {
        case .SOFTWARE:
            return "Type: \(getAttributeType()) \n content: \(String(bytes: attributeBody, encoding: String.Encoding.utf8) ) \n"
        default:
            return "Type: \(getAttributeType()) \n content: \(attributeBody) \n"
        }
    }
}

struct STUNPacketToSend {
    let msgRequestType: Array<UInt8> //2 bytes
    let bodyLength: Array<UInt8> //2 bytes
    let magicCookie: Array<UInt8> //4 bytes
    let transactionIdBindingRequest: Array<UInt8> //12 bytes
    let body: Array<UInt8> //?? bytes
    
    static func getBindingPacket() -> STUNPacketToSend  {
        return STUNPacketToSend(msgRequestType: [0x00, 0x01],
                                bodyLength:  [0x00, 0x00],
                                magicCookie: [0x21, 0x12, 0xA4, 0x42],
                                transactionIdBindingRequest: RandomTransactionID.getTransactionID(),
                                body: [])
    }
    
    func getPacketData() -> Data {
        return Data(msgRequestType + bodyLength + magicCookie + transactionIdBindingRequest)
    }
    
    static func getBindingAnswer(from answerPacket: Data) -> STUNPacketToSend {
        return STUNPacketToSend(msgRequestType: [UInt8](answerPacket[0..<2]),
                                bodyLength:  [UInt8](answerPacket[2..<4]),
                                magicCookie: [UInt8](answerPacket[4..<8]),
                                transactionIdBindingRequest: [UInt8](answerPacket[8..<20]),
                                body: [UInt8](answerPacket[20..<answerPacket.count]))
    }
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

open class STUNClient: NSObject {
    fileprivate weak var delegate: STUNClientDelegate?
    fileprivate var stunServer: String?
    fileprivate var updSocket: GCDAsyncUdpSocket?
    fileprivate var asyncQueue: DispatchQueue?

    fileprivate var bindingPacket: STUNPacketToSend?
    
    required public init(delegate: STUNClientDelegate?) {
        self.delegate = delegate
    }
    
    func getNATParams(stunServer: String, localPort: UInt16 = RandomLocalPort, stunPort: UInt16 = 3478) {
    
        delegate?.verbose("Initializing...")
        self.stunServer = stunServer
        
        if updSocket != nil {
            updSocket?.close()
        }
        asyncQueue = DispatchQueue(label: "STUNClient")
        updSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue:  asyncQueue)
        if localPort != RandomLocalPort {
            do {
                try updSocket?.bind(toPort: localPort)
            } catch {
                delegate?.error(errorText: "Can't bind localPort to UDP socket")
                updSocket = nil
                return
            }
        }
        
        do {
            try updSocket?.beginReceiving()
        } catch {
            delegate?.error(errorText: "Can't run UDP socket")
            updSocket = nil
            return
        }

        delegate?.verbose("Prepare binding packet to sent")

        bindingPacket = STUNPacketToSend.getBindingPacket()
        
   
        guard let dataToSend: Data = bindingPacket?.getPacketData(), dataToSend.count == 20  else {
            delegate?.error(errorText: "Can't prepare binding packet")
            updSocket = nil
            return
        }
        
        delegate?.verbose("Sending binding packet...")

        updSocket?.send(dataToSend, toHost: stunServer, port: stunPort, withTimeout: STUNRequestTimeout, tag: PacketsTags.BindingRequest.rawValue)
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
        
        delegate?.verbose("Received data from STUN server")
        
        // Checks
        //
        if data.count < 20 {
            delegate?.error(errorText: "Received data length too short")
            return;
        }
        
        let receivedPacket: STUNPacketToSend = STUNPacketToSend.getBindingAnswer(from: data)
        
        guard receivedPacket.magicCookie == (bindingPacket?.magicCookie)!, receivedPacket.transactionIdBindingRequest == (bindingPacket?.transactionIdBindingRequest)!  else {
             delegate?.error(errorText: "Received data from another request")
            return
        }

        //
        // Success Response: 0x0101
        // Error Response:   0x0111
        //
        if receivedPacket.msgRequestType != [0x01, 0x01] {
            delegate?.error(errorText: "Received error from STUN server")
            return
        }
        
        
        // get responss body length
        let responseBodyLength: Int = Int(receivedPacket.bodyLength[0]) * 256 + Int(receivedPacket.bodyLength[1])

        delegate?.verbose("Received data body has length: \(responseBodyLength)")

        guard responseBodyLength == receivedPacket.body.count else {
            delegate?.error(errorText: "Received data has unproper body length")
            return
        }
        
        var attributes: Array<STUNAttribute> = []
        var body: Array<UInt8> = receivedPacket.body
        while true {
            let attribute: STUNAttribute = STUNAttribute.getAttribute(from: body)
            body.removeFirst(attribute.getAttributeLength())
            delegate?.verbose("Attribute:  \(attribute.description()) \n")
            attributes.append(attribute)
            if body.count < 4 {
                break
            }
        }
        
        updSocket?.close()
        delegate?.completed(nat: NATParams(myExternalIP: "", myExternalPort: 2, natType: .FullCone))
        
/*
        int i = 20; // current reading position in the response binary data.  At 20 byte starts STUN Attributes
        //
        // STUN Attributes
        //
        // After the STUN header are zero or more attributes.  Each attribute
        // MUST be TLV encoded, with a 16-bit type, 16-bit length, and value.
        // Each STUN attribute MUST end on a 32-bit boundary.  As mentioned
        // above, all fields in an attribute are transmitted most significant
        // bit first.
        //
        //
        while(i < responseBodyLength+20){ // proccessing the response
            
            NSData *mappedAddressData = [data subdataWithRange:NSMakeRange(i, 2)];
            
            if([mappedAddressData isEqualToData:[NSData dataWithBytes:"\x00\x01" length:2]]){ // MAPPED-ADDRESS
                int maddrStartPos = i + 2 + 2 + 1 + 1;
                mport = [data subdataWithRange:NSMakeRange(maddrStartPos, 2)];
                maddr = [data subdataWithRange:NSMakeRange(maddrStartPos+2, 4)];
            }
            if([mappedAddressData isEqualToData:[NSData dataWithBytes:"\x80\x20" length:2]] || // XOR-MAPPED-ADDRESS
                [mappedAddressData isEqualToData:[NSData dataWithBytes:"\x00\x20" length:2]]){
                
                // apparently, all public stun servers tested use 0x8020 (in the Comprehension-optional range) -
                // as the XOR-MAPPED-ADDRESS Attribute type number instead of 0x0020 specified in RFC5389
                int xmaddrStartPos = i + 2 + 2 + 1 + 1;
                xmport=[data subdataWithRange:NSMakeRange(xmaddrStartPos, 2)];
                xmaddr=[data subdataWithRange:NSMakeRange(xmaddrStartPos+2, 4)];
            }
            
            i += 2;
            
            unsigned attribValueLength = 0;
            NSScanner *scanner = [NSScanner scannerWithString:[[[data subdataWithRange:NSMakeRange(i, 2)] description]
                substringWithRange:NSMakeRange(1, 4)]];
            [scanner scanHexInt:&attribValueLength];
            
            if(attribValueLength % 4 > 0){
                attribValueLength += 4 - (attribValueLength % 4); // adds stun attribute value padding
            }
            
            i += 2;
            i += attribValueLength;
        }
        
        
        NSString *ip = nil;
        NSString *port = nil;
        
        if(maddr != nil){
            ip = [self extractIP:maddr];
            port = [self extractPort:mport];
            
            STUNLog(@"MAPPED-ADDRESS: %@", maddr);
            STUNLog(@"mport: %@", mport);
        }else{
            STUNLog(@"STUN No MAPPED-ADDRESS found.");
        }
        
        if(xmaddr != nil){
            
            // XOR address
            int xmaddrInt = [self parseIntFromHexData:xmaddr];
            int magicCookieInt = [self parseIntFromHexData:magicCookie];
            //
            int32_t xoredAddr = CFSwapInt32HostToBig(magicCookieInt ^ xmaddrInt);
            NSData *xAddr = [NSData dataWithBytes:&xoredAddr length:4];
            ip = [self extractIP:xAddr];
            
            // XOR port
            int xmportInt = [self parseIntFromHexData:xmport];
            int magicCookieHighBytesInt = [self parseIntFromHexData:[magicCookie subdataWithRange:NSMakeRange(0, 2)]];
            //
            int32_t xoredPort = CFSwapInt16HostToBig(magicCookieHighBytesInt ^ xmportInt);
            NSData *xPort = [NSData dataWithBytes:&xoredPort length:2];
            port = [self extractPort:xPort];
            
            STUNLog(@"XOR-MAPPED-ADDRESS: %@", xAddr);
            STUNLog(@"xmport: %@", xPort);
            
        }else{
            STUNLog(@"STUN No XOR-MAPPED-ADDRESS found.");
        }
        
        NSNumber *isNatPortRandom = [NSNumber numberWithBool:[sock localPort] != [port intValue]];
        
        STUNLog(@"\n");
        STUNLog(@"=======STUN========");
        STUNLog(@"STUN IP: %@", ip);
        STUNLog(@"STUN Port: %@", port);
        STUNLog(@"STUN Port randomization: %d", [sock localPort] != [port intValue]);
        STUNLog(@"===================");
        STUNLog(@"\n");
        
        // notify delegate
        if([delegate respondsToSelector:@selector(didReceivePublicIPandPort:)]){
            NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:ip, publicIPKey, port, publicPortKey, isNatPortRandom, isPortRandomization, nil];
            [udpSocket setDelegate:delegate];
            [delegate didReceivePublicIPandPort:result];
        }
        */
    }
    
    public func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        delegate?.verbose("Socket has been closed")
    }
}
