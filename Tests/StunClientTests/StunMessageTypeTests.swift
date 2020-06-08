import XCTest
@testable import StunClient

final class StunMessageTypeTests: XCTestCase {
    func testToData() {
        // Given
        let msgType = StunMessageType.bindingRequest
        let expectedData: Data = Data([UInt8]([0x00, 0x01]))
        
        // When
        let data = msgType.toData()
        
        // Then
        XCTAssertEqual(data, expectedData)
    }
    
    func testFromCorrectData() {
        // Given
        let expectedMsgType = StunMessageType.bindingRequest
        let correctData: Data = Data([UInt8]([0x00, 0x01]))
        
        // When
        let msgType = StunMessageType.fromData(correctData)
        
        // Then
        XCTAssertNotNil(msgType, "Shouldn't be nil as data is correct")
        XCTAssertEqual(msgType, expectedMsgType)
    }
    
    func testFromWrongData() {
           // Given
           let wrongData: Data = Data([UInt8]([0x10, 0x01]))
           
           // When
           let msgType = StunMessageType.fromData(wrongData)
           
           // Then
           XCTAssertNil(msgType, "Should be nil as data is wrong")
       }
    
    func testFromEmptyData() {
        // Given
        let wrongData: Data = Data([UInt8]([]))
        
        // When
        let msgType = StunMessageType.fromData(wrongData)
        
        // Then
        XCTAssertNil(msgType, "Should be nil as data is empty")
    }

    static var allTests = [
        ("testToData", testToData),
        ("testFromCorrectData", testFromCorrectData),
        ("testFromWrongData", testFromWrongData),
        ("testFromEmptyData", testFromEmptyData),
    ]
}
