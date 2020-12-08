import XCTest
@testable import StunClient

final class StunPacketTests: XCTestCase {
    // Wrong length of packet
    let incorrectResponseTypeData: Data = bindingResponse.dropLast()
    
    func testParsePacketFromCorrectData() {
        // Given
        
        // When
        guard let packet = StunPacket.parse(from: bindingResponse) else {
            XCTAssert(false, "Packet should be parsed correctly")
            return
        }
        
        // Then
        XCTAssertEqual(packet.msgRequestType, [UInt8](StunMessageType.bindingResponse.toData()))
        XCTAssertEqual(packet.bodyLength, [UInt8]([0x0,0x0C])) // 12 bytes body length
        XCTAssertEqual(packet.magicCookie, MagicCookie)
        XCTAssertEqual(packet.attributes().count, 1) // Only one attribute is in the packet
        XCTAssertEqual(packet.attributes()[0].attributeType, .XOR_MAPPED_ADDRESS)
    }
    
    func testParsePacketFromCorrectBuffer() {
           // Given
            bindingResponse.withUnsafeBytes{ (bufferRawBufferPointer) -> Void in
                // When
                guard let packet = StunPacket.parse(from: bufferRawBufferPointer) else {
                    XCTAssert(false, "Packet should be parsed correctly")
                    return
                }
                
                // Then
                XCTAssertEqual(packet.msgRequestType, [UInt8](StunMessageType.bindingResponse.toData()))
                XCTAssertEqual(packet.bodyLength, [UInt8]([0x0,0x0C])) // 12 bytes body length
                XCTAssertEqual(packet.magicCookie, MagicCookie)
                XCTAssertEqual(packet.attributes().count, 1) // Only one attribute is in the packet
                XCTAssertEqual(packet.attributes()[0].attributeType, .XOR_MAPPED_ADDRESS)
            }
    }
    
    func testParsePacketFromIncorrectResponseData() {
        // Given
        
        // When
        let packet = StunPacket.parse(from: incorrectResponseTypeData)
        
        // Then
        XCTAssertNil(packet, "Packet shouldn't be parsed correctly")
    }
    
    func testParseAttributesFromCorrectData() {
        // Given
        let expectedAddress = "136.169.168.185"
        let expectedPort: UInt16 = 37332
        
        // When
        guard let packet = StunPacket.parse(from: bindingResponse) else {
            XCTAssert(false, "Packet should be parsed correctly")
            return
        }
        
        let attribute = packet.attributes()[0]
        
        guard let addressPacket = attribute.attributeType.getAttribute(from: Data((attribute.attributeBodyData)),
                                                                       transactionId: Array(bindingResponse[8..<20]),
                                                                       magicCookie: Array(bindingResponse[4..<8])) as? GeneralAddressAttribute else {
            XCTAssert(false, "Attribute from the packet should be parsed correctly")
            return
        }
        
        // Then
        XCTAssertEqual(addressPacket.address, expectedAddress)
        XCTAssertEqual(addressPacket.port, expectedPort)
    }
    
    func testParseAttributesFromCorrectIpv6Data() {
        // Given
        let expectedIpv6Address = "88a9:a8b9:dfef:ce05:3bd3:27c5:3bff:8565"
        let expectedPort: UInt16 = 37332

        // When
        guard let packet = StunPacket.parse(from: bindingResponseIpv6) else {
            XCTAssert(false, "Packet should be parsed correctly")
            return
        }
        
        let attribute = packet.attributes()[0]
        
        guard let addressPacket = attribute.attributeType.getAttribute(from: Data((attribute.attributeBodyData)),
                                                                       transactionId: Array(bindingResponse[8..<20]),
                                                                       magicCookie: Array(bindingResponse[4..<8])) as? GeneralAddressAttribute else {
            XCTAssert(false, "Attribute from the packet should be parsed correctly")
            return
        }
        
        // Then
        XCTAssertEqual(addressPacket.address, expectedIpv6Address)
        XCTAssertEqual(addressPacket.port, expectedPort)
    }

    func testIfResponseIsCorrectSuccess() {
        // Given
        let requestPacket = StunPacket.parse(from: bindingRequest)!
        let responsePacket = StunPacket.parse(from: bindingResponse)!
        
        // When
        let res = requestPacket.isCorrectResponse(responsePacket)
        
        // Then
        XCTAssertTrue(res)
    }
    
    func testIfResponseIsCorrectFailed() {
        // Given
        let requestPacket = StunPacket.parse(from: bindingRequest)!
        let responsePacket = StunPacket.parse(from: sharedSecretError)! // Response doesn't match request
        
        // When
        let res = requestPacket.isCorrectResponse(responsePacket)
        
        // Then
        XCTAssertFalse(res)
    }
    
    func testIfResponseIsCorrectFailedTransactionId() {
        // Given
        let requestPacket = StunPacket.parse(from: bindingRequest)!
        
        // Response's transaction id doesn't match request
        var wrongBindingResponse = bindingResponse
        wrongBindingResponse[8] = 0
        let responsePacket = StunPacket.parse(from: wrongBindingResponse)! //
        
        // When
        let res = requestPacket.isCorrectResponse(responsePacket)
        
        // Then
        XCTAssertFalse(res)
    }

    static var allTests = [
        ("testParsePacketFromCorrectData", testParsePacketFromCorrectData),
        ("testParseAttributesFromCorrectData", testParseAttributesFromCorrectData),
        ("testParsePacketFromCorrectBuffer", testParsePacketFromCorrectBuffer),
        ("testParsePacketFromIncorrectResponseData", testParsePacketFromIncorrectResponseData),
        ("testIfResponseIsCorrectSuccess", testIfResponseIsCorrectSuccess),
        ("testIfResponseIsCorrectFailed", testIfResponseIsCorrectFailed),
        ("testIfResponseIsCorrectFailedTransactionId", testIfResponseIsCorrectFailedTransactionId),
    ]
}
