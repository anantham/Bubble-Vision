//
//  BubbleAnchor.swift
//  Bubble Vision
//
//  Data model for persistent bubble panes
//

import Foundation
import simd

/// Represents a single bubble pane anchor with visual properties
struct BubbleAnchor: Codable, Identifiable {
    let id: UUID
    var transform: CodableTransform
    var size: SIMD2<Float>    // meters (width, height)
    var hueSeed: Float        // drives rainbow phase shift
    var createdAt: Date

    init(id: UUID = UUID(),
         transform: simd_float4x4,
         size: SIMD2<Float> = SIMD2<Float>(0.6, 0.4),
         hueSeed: Float = Float.random(in: 0...1),
         createdAt: Date = Date())
    {
        self.id = id
        self.transform = CodableTransform(transform)
        self.size = size
        self.hueSeed = hueSeed
        self.createdAt = createdAt
    }
}

/// Wrapper to make simd_float4x4 Codable
struct CodableTransform: Codable {
    var columns: [SIMD4<Float>]  // Array is Codable, tuple is not

    init(_ matrix: simd_float4x4) {
        self.columns = [
            matrix.columns.0,
            matrix.columns.1,
            matrix.columns.2,
            matrix.columns.3
        ]
    }

    var matrix: simd_float4x4 {
        simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
    }
}

/// Session persistence container
struct SessionState: Codable {
    var bubbles: [BubbleAnchor]

    init(bubbles: [BubbleAnchor] = []) {
        self.bubbles = bubbles
    }
}
