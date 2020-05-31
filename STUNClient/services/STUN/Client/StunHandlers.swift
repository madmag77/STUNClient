//
//  StunPacketHandler.swift
//  STUNClient
//
//  Created by Artem Goncharov on 31/5/20.
//  Copyright © 2020 MadMag. All rights reserved.
//

import Foundation
import NIO

/// Decode byte buffer to Stun packet
final class StunCodec: ByteToMessageDecoder {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = StunPacket
        
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let packet = buffer.withUnsafeReadableBytes({pointer in StunPacket.parse(from: pointer)}) else {
             return .needMoreData
        }
        
        buffer.moveReaderIndex(to: packet.toData().count)
        context.fireChannelRead(self.wrapInboundOut(packet))
        return .continue
    }
}

/// Convert AddressEnvelope to Byte buffer  for ByteToMessageDecoder
final class EnvelopToByteBufferConverter: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias InboundOut = ByteBuffer
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        let byteBuffer = envelope.data
        context.fireChannelRead(self.wrapInboundOut(byteBuffer))
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[EnvelopToByteBufferConverter] error: ", error)
        context.close(promise: nil)
    }
}

/// Handle reading attributes and errors
final class StunInboundHandler: ChannelInboundHandler {
    public typealias InboundIn = StunPacket
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    public typealias ErrorHandler = ((StunError) -> ())?
    
    private let errorHandler: ErrorHandler
    private let attributesHandler:  ([StunAttribute]) -> ()
   
    init(errorHandler: ErrorHandler, attributesHandler: @escaping ([StunAttribute]) -> ()) {
        self.errorHandler = errorHandler
        self.attributesHandler = attributesHandler
    }
    
    public func sendBindingRequest(channel: Channel, toStunServerAddress address: String, toStunServerPort port: Int) {
        let requestData = StunPacket.makeBindingRequest().toData()
        
        let remoteAddress: SocketAddress
        do {
            remoteAddress = try SocketAddress.makeAddressResolvingHost(address, port: port)
        } catch {
            errorHandler?(.cantResolveStunServerAddress)
            return
        }
        
        var buffer = channel.allocator.buffer(capacity: requestData.count)
        buffer.writeBytes(requestData)

        let envolope = AddressedEnvelope<ByteBuffer>(remoteAddress: remoteAddress, data: buffer)
        
        channel.writeAndFlush(self.wrapOutboundOut(envolope), promise: nil)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let packet = self.unwrapInboundIn(data)
        
        attributesHandler(packet.attributes())
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        errorHandler?(.cantRead(error.localizedDescription))
        context.close(promise: nil)
    }
}
