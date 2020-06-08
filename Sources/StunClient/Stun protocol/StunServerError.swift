import Foundation

public enum StunServerError: UInt16 {
    case unknown = 0
    case badRequest = 400
    case unauthorized = 401
    case unknownAttribute = 420
    case staleCredentials = 430
    case integrityCheckFailure = 431
    case missingUsername = 432
    case useTLS = 433
    case serverError = 500
    case globalFailure = 600
}
