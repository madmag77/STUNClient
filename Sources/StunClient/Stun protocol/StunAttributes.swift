import Foundation

/// Umbrella protocol for all stun atrributes with family, address and port
protocol GeneralAddressAttribute {
    var family: String { get }
    var address: String { get }
    var port: UInt16 { get }
}

protocol Attribute {
    var description: String {get}
}

enum AttributeType: UInt16 {
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
    
    func getAttribute(from data: Data, transactionId: [UInt8], magicCookie: [UInt8]) -> Attribute? {
        switch self {
        case .MAPPED_ADDRESS,
             .RESPONSE_ORIGIN,
             .RESPONSE_ADDRESS,
             .CHANGED_ADDRESS,
             .SOURCE_ADDRESS,
             .OTHER_ADDRESS:
            guard let attribute: NORMAL_ADDRESS_ATTRIBUTE = NORMAL_ADDRESS_ATTRIBUTE.fromData(data) else {
                return nil
            }
            return attribute
            
        case .USERNAME, .PASSWORD, .SOFTWARE:
            guard let attribute: STRING_ATTRIBUTE = STRING_ATTRIBUTE.fromData(data) else {
                return nil
            }
            return attribute
            
        case .ERROR_CODE:
            guard let attribute: ERROR_CODE_ATTRIBUTE = ERROR_CODE_ATTRIBUTE.fromData(data)
                else {
                    return nil
            }
            return attribute
            
        case .XOR_MAPPED_ADDRESS:
            guard let attribute = XOR_MAPPED_ADDRESS_ATTRIBUTE.fromData(data,
                                                                        transactionId: transactionId,
                                                                        magicCookie: magicCookie) else {
                return nil
            }
            return attribute
        default:
            return STRING_ATTRIBUTE.getFromString("raw content: \(data) \n")
        }
    }
}

struct STRING_ATTRIBUTE: Attribute {
    let content: String
    
    static func fromData(_ data: Data) -> STRING_ATTRIBUTE? {
        guard data.count > 0  else { return nil}
        return STRING_ATTRIBUTE(content: String(data: data, encoding: .utf8)!)
    }
    
    static func getFromString(_ string: String) -> STRING_ATTRIBUTE {
        return STRING_ATTRIBUTE(content: string)
    }
    
    var description: String {
        return content
    }
    
    func toArray() -> [UInt8] {
        return [UInt8](content.data(using: .utf8) ?? Data())
    }
}

struct NORMAL_ADDRESS_ATTRIBUTE: Attribute {
    let protocolFamily: ProtocolFamily
    let port: UInt16
    let ipAddress: IpAddress
    
    var description: String {
        return "Family: \(self.protocolFamily.description) \n Port: \(UInt16(self.port))  \n Address: \(ipAddress.description)"
    }
    
    static func fromData(_ data: Data) -> NORMAL_ADDRESS_ATTRIBUTE? {
        guard data.count >= 8, let protocolFamily = ProtocolFamily(rawValue: data[1]) else {
            return nil
        }
        
        let port = UInt16(data[2]) * 256 + UInt16(data[3])
        return NORMAL_ADDRESS_ATTRIBUTE(protocolFamily: protocolFamily,
                                        port: port,
                                        ipAddress: protocolFamily == ProtocolFamily.ipv4 ?
                                            convertDataToAddressIpv4(Array(data[4..<8])) :
                                            convertDataToAddressIpv6(Array(data[4..<20]))
        )
    }
    
    static func convertDataToAddressIpv4(_ data: [UInt8]) -> IpAddress {
        return Ipv4(with: data)
    }
    
    static func convertDataToAddressIpv6(_ data: [UInt8]) -> IpAddress {
        return Ipv6(with: data)
    }
}

extension NORMAL_ADDRESS_ATTRIBUTE: GeneralAddressAttribute {
    var address: String {
       return ipAddress.description
    }
    
    var family: String {
        return protocolFamily.description
    }
}


struct XOR_MAPPED_ADDRESS_ATTRIBUTE: Attribute {
    let protocolFamily: ProtocolFamily
    let port: UInt16
    let ipAddress: IpAddress

    var description: String {
        return "Family: \(self.protocolFamily.description) \n Port: \(UInt16(self.port))  \n Address: \(ipAddress.description)"
    }
    
    static func fromData(_ data: Data, transactionId: [UInt8], magicCookie: [UInt8]) -> XOR_MAPPED_ADDRESS_ATTRIBUTE? {
        guard let protocolFamily = ProtocolFamily(rawValue: data[1]) else { return nil }
        
        let port = UInt16(data[2] ^ MagicCookie[0]) * 256 + UInt16(data[3] ^ MagicCookie[1])
        return XOR_MAPPED_ADDRESS_ATTRIBUTE(protocolFamily: protocolFamily,
                                            port: port,
                                            ipAddress: protocolFamily == ProtocolFamily.ipv4 ?
                                                convertDataToAddressIpv4(Array(data[4..<8]),
                                                                         magicCookie: magicCookie) :
                                                convertDataToAddressIpv6(Array(data[4..<20]),
                                                                         magicCookie: magicCookie,
                                                                         transactionId: transactionId))
    }
    
    static func convertDataToAddressIpv4(_ data: [UInt8],
                                         magicCookie: [UInt8]) -> IpAddress {
        return Ipv4(with: (0..<4).map{data[$0] ^ magicCookie[$0]})
    }
    
    static func convertDataToAddressIpv6(_ data: [UInt8],
                                         magicCookie: [UInt8],
                                         transactionId: [UInt8]) -> IpAddress {
        return Ipv6(with: (0..<16).map{data[$0] ^ (magicCookie + transactionId)[$0]})
    }
}

extension XOR_MAPPED_ADDRESS_ATTRIBUTE: GeneralAddressAttribute {
    var address: String {
       return ipAddress.description
    }
    
    var family: String {
        return protocolFamily.description
    }
}

struct ERROR_CODE_ATTRIBUTE: Attribute {
    let errorCode: StunServerError
    let description: String
    
    static func fromData(_ data: Data) -> ERROR_CODE_ATTRIBUTE? {
        guard data.count >= 4 else {
            return nil
        }
        return ERROR_CODE_ATTRIBUTE(errorCode: StunServerError(rawValue: UInt16(data[2]) * 100 + UInt16(data[3])) ?? .unknown,
                                    description: String(data: data.subdata(in: Range(uncheckedBounds: (lower: 4, upper: data.count))),
                                                        encoding: .utf8) ?? "")
    }
    
    func getDescription() -> String {
        return "ErrorCode: \(errorCode), description: \(description)"
    }
}

struct REQUESTED_ADDRESS_FAMILY: Attribute {
    let protocolFamily: ProtocolFamily
    let type = AttributeType.REQUESTED_ADDRESS_FAMILY
    let length = 4
    
    var description: String {
        return "Family: \(protocolFamily.description)"
    }
    
    func toData() -> [UInt8] {
        return [UInt8(type.rawValue / 256),
                UInt8(type.rawValue % 256),
                UInt8(length / 256),
                UInt8(length % 256),
                0x00, 0x00, 0x00,
                protocolFamily.rawValue]
    }
}
