
import XCTest

let bindingRequest: Data = Data([UInt8]([0, 1, 0, 0, 33, 18, 164, 66, 244, 227, 151, 148, 22, 163, 40, 199, 220, 144, 167, 105]))
let bindingResponse: Data = Data([UInt8]([1, 1, 0, 12, 33, 18, 164, 66, 244, 227, 151, 148, 22, 163, 40, 199, 220, 144, 167, 105, 0, 32, 0, 8, 0, 1, 176, 198, 169, 187, 12, 251]))
let bindingResponseIpv6: Data = Data([UInt8]([1, 1, 0, 24, 33, 18, 164, 66, 244, 227, 151, 148, 22, 163, 40, 199, 220, 144, 167, 105, 0, 32, 0, 20, 0, 2, 176, 198, 169, 187, 12, 251, 43, 12, 89, 145, 45, 112, 15, 2, 231, 111, 34, 12]))
let bindingError = Data([UInt8]([1, 17, 0, 10, 33, 18, 164, 66, 244, 227, 151, 148, 22, 163, 40, 199, 220, 144, 167, 105, 0, 9, 0, 6, 0, 0, 4, 0, 110, 111]))
let sharedSecretError = Data([UInt8]([1, 18, 0, 8, 33, 18, 164, 66, 244, 227, 151, 148, 22, 163, 40, 199, 220, 144, 167, 105, 0, 9, 0, 2, 4, 0, 176, 198]))
