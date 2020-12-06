enum ProtocolFamily: UInt8 {
    case ipv4 = 0x01
    case ipv6 = 0x02
}

extension ProtocolFamily {
    var description: String {
        switch self {
        case .ipv4:
            return "IPv4"
        case .ipv6:
            return "IPv6"
        }
    }
}

protocol IpAddress {
    init(with data: [UInt8])
    var description: String { get }
}

struct Ipv4: IpAddress {
    private let addr: [UInt8]
    
    init(with data: [UInt8]) {
        self.addr = data
    }
    
    var description: String {
        return addr
            .map { String($0) }
            .joined(separator: ".")
    }
}

struct Ipv6: IpAddress {
    private let addr: [UInt8]
    
    init(with data: [UInt8]) {
        self.addr = data
    }
    
    var description: String {
        var res: [String] = []
        for i in (0..<8) {
            res.append(String(format:"%02x%02x", addr[2*i], addr[2*i + 1]))
        }
        return res.joined(separator: ":")
    }
}
