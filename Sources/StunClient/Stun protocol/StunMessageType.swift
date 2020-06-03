import Foundation

enum StunMessageType: UInt16 {
    case bindingRequest = 0x0001
    case bindingResponse = 0x0101
    case bindingErrorResponse = 0x0111
    case sharedSecretRequest = 0x0002
    case sharedSecretResponse = 0x0102
    case sharedSecretErrorResponse = 0x0112
}
