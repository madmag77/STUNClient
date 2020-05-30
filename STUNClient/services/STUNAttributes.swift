//
//  STUNAttributes.swift
//  STUNClient
//
//  Created by Artem Goncharov on 09/04/2017.
//  Copyright © 2017 MadMag. All rights reserved.
//

import Foundation

protocol Packet {
    var description: String {get}
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
    
    func getPacket(from data: Data) throws -> Packet {
        switch self {
        case .MAPPED_ADDRESS, .RESPONSE_ORIGIN, .RESPONSE_ADDRESS, .CHANGED_ADDRESS, .SOURCE_ADDRESS, .OTHER_ADDRESS:
            guard let packet: NORMAL_ADDRESS_ATTRIBUTE_PACKET = NORMAL_ADDRESS_ATTRIBUTE_PACKET.getFromData(data) else {
                throw STUNError.cantConvertValue
            }
            return packet
            
        case .USERNAME, .PASSWORD, .SOFTWARE:
            guard let packet: STRING_PACKET = STRING_PACKET.getFromData(data) else {
                throw STUNError.cantConvertValue
            }
            return packet
            
        case .ERROR_CODE:
            guard let packet: ERROR_CODE_ATTRIBUTE_PACKET = ERROR_CODE_ATTRIBUTE_PACKET.getFromData(data)
                else {
                    throw STUNError.cantConvertValue
            }
            return packet
            
        case .XOR_MAPPED_ADDRESS:
            guard let packet = XOR_MAPPED_ADDRESS_ATTRIBUTE_PACKET.getFromData(data) else {
                throw STUNError.cantConvertValue
            }
            return packet
            
        default:
            return STRING_PACKET.getFromString("raw content: \(data) \n")
        }
    }
}

struct STRING_PACKET: Packet {
    let packet: String
    static func getFromData(_ data: Data) -> STRING_PACKET? {
        guard data.count > 0  else { return nil}
        return STRING_PACKET(packet: String(data: data, encoding: .utf8)!)
    }
    
    static func getFromString(_ string: String) -> STRING_PACKET {
        return STRING_PACKET(packet: string)
    }
    
    var description: String {
        return packet
    }
}

struct NORMAL_ADDRESS_ATTRIBUTE_PACKET: Packet {
    let family: UInt8
    let port: UInt16
    let addr1: UInt8
    let addr2: UInt8
    let addr3: UInt8
    let addr4: UInt8
    
    var description: String {
        return "Family: \(self.family) \n Port: \(UInt16(self.port))  \n Address: \(self.addr1).\(self.addr2).\(self.addr3).\(self.addr4)"
    }
    
    static func formPacket(with address:String, and port:UInt16) -> NORMAL_ADDRESS_ATTRIBUTE_PACKET {
        let address: [UInt8] = NORMAL_ADDRESS_ATTRIBUTE_PACKET.address(from: address)
        return NORMAL_ADDRESS_ATTRIBUTE_PACKET(
            family: 1,
            port: port,
            addr1: address[0],
            addr2: address[1],
            addr3: address[2],
            addr4: address[3]
        )
    }
    
    static func getFromData(_ data: Data) -> NORMAL_ADDRESS_ATTRIBUTE_PACKET? {
        guard data.count == 8 else {
            return nil
        }
        let port = UInt16(data[2]) * 256 + UInt16(data[3])
        return NORMAL_ADDRESS_ATTRIBUTE_PACKET(family: data[1],
                                               port: port,
                                               addr1: data[4],
                                               addr2: data[5],
                                               addr3: data[6],
                                               addr4: data[7]
        )
    }
    
    func getPacketData() -> [UInt8] {
        return [0x0, family, UInt8(port / 256), UInt8(port % 256), addr1, addr2, addr3, addr4]
    }
    
    static func address(from string: String) -> [UInt8] {
        let components = string.components(separatedBy: ".")
        let address: [UInt8] = components.flatMap {
            UInt8($0)
        }
        return address
    }
}

struct XOR_MAPPED_ADDRESS_ATTRIBUTE_PACKET: Packet {
    let family: UInt8
    let port: UInt16
    let addr1: UInt8
    let addr2: UInt8
    let addr3: UInt8
    let addr4: UInt8
    
    var description: String {
        return "Family: \(self.family) \n Port: \(UInt16(self.port))  \n Address: \(self.addr1).\(self.addr2).\(self.addr3).\(self.addr4)"
    }
    
    static func getFromData(_ data: Data) -> XOR_MAPPED_ADDRESS_ATTRIBUTE_PACKET? {
        guard data.count == 8 else {
            return nil
        }
        let port = UInt16(data[2] ^ MagicCookie[0]) * 256 + UInt16(data[3] ^ MagicCookie[1])
        return XOR_MAPPED_ADDRESS_ATTRIBUTE_PACKET(family: data[1],
                                                   port: port,
                                                   addr1: data[4] ^ MagicCookie[0],
                                                   addr2: data[5] ^ MagicCookie[1],
                                                   addr3: data[6] ^ MagicCookie[2],
                                                   addr4: data[7] ^ MagicCookie[3]
        )
    }
}

struct ERROR_CODE_ATTRIBUTE_PACKET: Packet {
    let errorCode: STUNServerError
    let description: String
    
    static func getFromData(_ data: Data) -> ERROR_CODE_ATTRIBUTE_PACKET? {
        guard data.count > 4 else {
            return nil
        }
        return ERROR_CODE_ATTRIBUTE_PACKET(errorCode: STUNServerError(rawValue: UInt16(data[2]) * 100 + UInt16(data[3]))!,
                                           description: String(data: data.subdata(in: Range(uncheckedBounds: (lower: 4, upper: data.count - 1))), encoding: .utf8)!)
    }
    
    func getDescription() -> String {
        return "ErrorCode: \(errorCode), description: \(description)"
    }
}

struct STUNAttribute {
    let attributeType: [UInt8]
    let attributeLength: [UInt8]
    let attributeBody: [UInt8]
    
    static func getAttribute(from data: [UInt8]) throws -> STUNAttribute {
        return STUNAttribute(attributeType: [UInt8](data[0..<2]),
                             attributeLength:  [UInt8](data[2..<4]),
                             attributeBody: [UInt8](data[4..<4 + Int(data[2]) * 256 + Int(data[3])]))
    }
    
    static func formAttribute(type: AttributeType, body:[UInt8]) -> STUNAttribute {
        return STUNAttribute(attributeType: [UInt8(type.rawValue / 256), UInt8(type.rawValue % 256)],
                             attributeLength: [UInt8(body.count / 256), UInt8(body.count % 256)],
                             attributeBody: body
        )
    }
    
    func getAttributeLength() -> Int {
        return attributeType.count + attributeLength.count + attributeBody.count
    }
    
    func getAttributeType() -> AttributeType {
        return AttributeType(rawValue: Int(self.attributeType[0]) * 256 + Int(self.attributeType[1])) ?? .UNKNOWN
    }
    
    func toArray() -> [UInt8] {
        return self.attributeType + self.attributeLength + self.attributeBody
    }
    
    func description() throws -> String {
        return try "\(getAttributeType()) \n \(getAttributeType().getPacket(from: Data(self.attributeBody)).description)"
    }
}
