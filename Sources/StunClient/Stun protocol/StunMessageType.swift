import Foundation

enum StunMessageType: UInt16 {
    case bindingRequest = 0x0001
    case bindingResponse = 0x0101
    case bindingErrorResponse = 0x0111
    case sharedSecretRequest = 0x0002
    case sharedSecretResponse = 0x0102
    case sharedSecretErrorResponse = 0x0112
    
    func toData() -> Data {
        return Data([UInt8(self.rawValue >> 8), UInt8(self.rawValue & 0xFF)])
    }
    
    static func fromData(_ data: Data) -> StunMessageType? {
        guard data.count >= 2 else { return nil }
        
        return StunMessageType(rawValue: UInt16(data[0]) * 256 + UInt16(data[1]))
    }
    
    func isCorrectResponse(_ responseType: StunMessageType) -> Bool {
        switch (self, responseType) {
            case
            (.bindingRequest, .bindingResponse),
            (.bindingRequest, .bindingErrorResponse),
            (.sharedSecretRequest, .sharedSecretResponse),
            (.sharedSecretRequest, .sharedSecretErrorResponse):
            return true
        default:
            return false
        }
    }
    
    func isErrorType() -> Bool {
        switch (self) {
        case .bindingErrorResponse, .sharedSecretErrorResponse:
            return true
        default:
            return false
        }
    }
}
