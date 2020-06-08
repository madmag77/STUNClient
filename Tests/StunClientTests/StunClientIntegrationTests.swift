import XCTest
@testable import StunClient
import NIO

final class StunClientIntegrationTests: XCTestCase {
    
    func testServerDoesntAnswer() {
        
        // Given
        let readTimeoutInMilliseconds: Int64 = 100
        
        // Two times bigger than read timout
        let semaphoreTimeoutInNanoseconds: Int64 = 2 * readTimeoutInMilliseconds * 1000 * 1000
        let semaphore = DispatchSemaphore(value: 0)
        
        // Supposed that there is no STUN server run locally on port 19302
        let client = StunClient(stunIpAddress: "127.0.0.1", stunPort: 19302, localPort: UInt16(15702), timeoutInMilliseconds: readTimeoutInMilliseconds)
        let successCallback: (String, Int) -> () = { (myAddress: String, myPort: Int) in
            
            // Then
            XCTAssert(false, "Not supposed to trigger success callbak")
            semaphore.signal()
        }
        let errorCallback: (StunError) -> () = { error in
            
            // Then
            XCTAssertEqual(error, StunError.readTimeout, "The error should be readTimeout")
            semaphore.signal()
        }
        
        // When
        client
            .whoAmI()
            .ifWhoAmISuccessful(successCallback)
            .ifError(errorCallback)
            .start()
        
        let res = semaphore.wait(timeout: DispatchTime.now() + DispatchTimeInterval.nanoseconds(Int(semaphoreTimeoutInNanoseconds)))
        
        // Then
        XCTAssertNotEqual(res, .timedOut, "StunClient should report timeout first and trigger semaphore")
    }

    func testSuccessfullAnswer() {
        
        // Given
        var addressToCheck: String = ""
        var portToCheck: Int = 0
        
        let localServerAddress = "127.0.0.1"
        let stunPort = 19302
        let responseAddress = "136.169.168.185"
        let responsePort = 37332
        let localPort = 15702
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try group.syncShutdownGracefully())
        }

        class TestStunServerHandler: ChannelInboundHandler {
            typealias InboundIn = AddressedEnvelope<ByteBuffer>
            typealias OutboundOut = AddressedEnvelope<ByteBuffer>
            let localPort: Int
            let localServerAddress: String
            
            // Sample binding response
            let sampleAnswer: [UInt8] = [UInt8](bindingResponse)
            
            init(localServerAddress: String, localPort: Int) {
                self.localServerAddress = localServerAddress
                self.localPort = localPort
            }
            
            public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let envelope = self.unwrapInboundIn(data)
                let byteBuffer = envelope.data
                guard let packet = byteBuffer.withUnsafeReadableBytes({pointer in StunPacket.parse(from: pointer)}) else {
                     XCTAssert(false, "Client's request is supposed to be correct")
                    return
                }
                
                // Change the transactional id to the one from the request
                let responseToSend = [UInt8](sampleAnswer[0..<8]) + packet.transactionIdBindingRequest + [UInt8](sampleAnswer[20..<sampleAnswer.count])
                
                let remoteAddress: SocketAddress = try! SocketAddress.makeAddressResolvingHost(localServerAddress, port: localPort)
                    
                var buffer = context.channel.allocator.buffer(capacity: responseToSend.count)
                buffer.writeBytes(responseToSend)
                let envolope = AddressedEnvelope<ByteBuffer>(remoteAddress: remoteAddress, data: buffer)
                
                context.writeAndFlush(self.wrapOutboundOut(envolope), promise: nil)
            }
        }

        let serverChannel = try! DatagramBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .channelInitializer { channel in
            channel.pipeline.addHandler(TestStunServerHandler(localServerAddress: localServerAddress, localPort: localPort))
        }.bind(host: localServerAddress, port: stunPort).wait()

        defer {
            XCTAssertNoThrow(try serverChannel.close().wait())
        }

       let readTimeoutInMilliseconds: Int64 = 100
        
        // Two times bigger than read timout
        let semaphoreTimeoutInNanoseconds: Int64 = 2 * readTimeoutInMilliseconds * 1000 * 1000
        let semaphore = DispatchSemaphore(value: 0)
        
        let client = StunClient(stunIpAddress: localServerAddress, stunPort: UInt16(stunPort), localPort: UInt16(localPort), timeoutInMilliseconds: readTimeoutInMilliseconds)
        let successCallback: (String, Int) -> () = { (myAddress: String, myPort: Int) in
            
            // Then
            addressToCheck = myAddress
            portToCheck = myPort
            semaphore.signal()
        }
        let errorCallback: (StunError) -> () = { error in
            
            // Then
            XCTAssert(false, "Not supposed to catch an error: \(error.errorDescription)")
            semaphore.signal()
        }
        
        // When
        client
            .whoAmI()
            .ifWhoAmISuccessful(successCallback)
            .ifError(errorCallback)
            .start()
        
        let res = semaphore.wait(timeout: DispatchTime.now() + DispatchTimeInterval.nanoseconds(Int(semaphoreTimeoutInNanoseconds)))
        
        // Then
        XCTAssertNotEqual(res, .timedOut, "StunClient should report timeout first and trigger semaphore")
        
        XCTAssertEqual(addressToCheck, responseAddress, "Address from server should match")
        XCTAssertEqual(portToCheck, responsePort, "Port from server should match")
    }
    
    func testServerReturnError() {
        
        // Given
        let localServerAddress = "127.0.0.1"
        let stunPort = 19303
        let localPort = 15703
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try group.syncShutdownGracefully())
        }

        class TestStunServerHandler: ChannelInboundHandler {
            typealias InboundIn = AddressedEnvelope<ByteBuffer>
            typealias OutboundOut = AddressedEnvelope<ByteBuffer>
            let localPort: Int
            let localServerAddress: String
            
            // Sample binding response
            let sampleAnswer: [UInt8] = [UInt8](bindingError)
            
            init(localServerAddress: String, localPort: Int) {
                self.localServerAddress = localServerAddress
                self.localPort = localPort
            }
            
            public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let envelope = self.unwrapInboundIn(data)
                let byteBuffer = envelope.data
                guard let packet = byteBuffer.withUnsafeReadableBytes({pointer in StunPacket.parse(from: pointer)}) else {
                     XCTAssert(false, "Client's request is supposed to be correct")
                    return
                }
                
                // Change the transactional id to the one from the request
                let responseToSend = [UInt8](sampleAnswer[0..<8]) + packet.transactionIdBindingRequest + [UInt8](sampleAnswer[20..<sampleAnswer.count])
                
                let remoteAddress: SocketAddress = try! SocketAddress.makeAddressResolvingHost(localServerAddress, port: localPort)
                    
                var buffer = context.channel.allocator.buffer(capacity: responseToSend.count)
                buffer.writeBytes(responseToSend)
                let envolope = AddressedEnvelope<ByteBuffer>(remoteAddress: remoteAddress, data: buffer)
                
                context.writeAndFlush(self.wrapOutboundOut(envolope), promise: nil)
            }
        }

        let serverChannel = try! DatagramBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .channelInitializer { channel in
            channel.pipeline.addHandler(TestStunServerHandler(localServerAddress: localServerAddress, localPort: localPort))
        }.bind(host: localServerAddress, port: stunPort).wait()

        defer {
            XCTAssertNoThrow(try serverChannel.close().wait())
        }

       let readTimeoutInMilliseconds: Int64 = 100
        
        // Two times bigger than read timout
        let semaphoreTimeoutInNanoseconds: Int64 = 2 * readTimeoutInMilliseconds * 1000 * 1000
        let semaphore = DispatchSemaphore(value: 0)
        
        let client = StunClient(stunIpAddress: localServerAddress, stunPort: UInt16(stunPort), localPort: UInt16(localPort), timeoutInMilliseconds: readTimeoutInMilliseconds)
        let successCallback: (String, Int) -> () = { (myAddress: String, myPort: Int) in
            
            // Then
             XCTAssert(false, "Not supposed to trigger success callbak")
            semaphore.signal()
        }
        let errorCallback: (StunError) -> () = { error in
            
            // Then
            XCTAssertEqual(error, StunError.stunServerError(.badRequest), "Stun server error is supposed to be caught")
            semaphore.signal()
        }
        
        // When
        client
            .whoAmI()
            .ifWhoAmISuccessful(successCallback)
            .ifError(errorCallback)
            .start()
        
        let res = semaphore.wait(timeout: DispatchTime.now() + DispatchTimeInterval.nanoseconds(Int(semaphoreTimeoutInNanoseconds)))
        
        // Then
        XCTAssertNotEqual(res, .timedOut, "StunClient should report timeout first and trigger semaphore")
    }

    
    static var allTests = [
        ("testServerDoesntAnswer", testServerDoesntAnswer),
        ("testSuccessfullAnswer", testSuccessfullAnswer),
        ("testServerReturnError", testServerReturnError),
    ]
}
