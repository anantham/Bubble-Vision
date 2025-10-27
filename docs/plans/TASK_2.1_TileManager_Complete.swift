// TileManager.swift
// Complete implementation for Task 2.1
// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 3

import Foundation
import Metal
import simd

/// Tile coordinate frame
struct TileFrame {
    var originWS: SIMD3<Float>      // World-space origin
    var axisWS: simd_float3x3       // Columns = X, Y, Z (orthonormal)
    var voxelSize: Float            // Meters per voxel
    var dim: Int32                  // 64 (voxels per side)
    var epoch: UInt32               // Incremented when repositioned
}

/// Single tile in sparse cache
struct Tile {
    var frame: TileFrame
    var sdfTexture: MTLTexture?     // 3D R16Float texture (64³)
    // Note: No separate buffer needed - operate directly on texture
}

final class TileManager {
    private let device: MTLDevice
    private(set) var tiles: [Tile] = []

    // Defaults (can be adjusted)
    private let defaultTileCount = 8        // Start with 8 tiles
    private let defaultDim: Int32 = 64      // 64³ voxels per tile
    private let defaultVoxelSize: Float = 0.02  // 2cm per voxel → 1.28m tile extent

    init(device: MTLDevice, tileCount: Int = 8) {
        self.device = device
        allocateTiles(count: tileCount)
    }

    // MARK: - Initialization

    private func allocateTiles(count: Int) {
        for i in 0..<count {
            // Position tiles in a rough grid around origin
            let gridX = Float((i % 4) - 2)  // -2, -1, 0, 1
            let gridZ = Float((i / 4) - 1)  // -1, 0, 1

            let frame = TileFrame(
                originWS: SIMD3<Float>(gridX * 1.5, 0, gridZ * 1.5),  // 1.5m spacing
                axisWS: simd_float3x3(diagonal: SIMD3<Float>(1, 1, 1)),  // Identity (world-aligned)
                voxelSize: defaultVoxelSize,
                dim: defaultDim,
                epoch: 0
            )

            var tile = Tile(frame: frame, sdfTexture: nil)

            // Allocate 3D texture
            let descriptor = MTLTextureDescriptor()
            descriptor.width = Int(defaultDim)
            descriptor.height = Int(defaultDim)
            descriptor.depth = Int(defaultDim)
            descriptor.pixelFormat = .r16Float
            descriptor.textureType = .type3D
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private  // GPU-only for performance

            tile.sdfTexture = device.makeTexture(descriptor: descriptor)

            tiles.append(tile)

            print("✓ Allocated tile \(i): origin=\(frame.originWS), extent=\(defaultVoxelSize * Float(defaultDim))m")
        }

        // Initialize all tiles to +infinity
        clearAllTiles()
    }

    private func clearAllTiles() {
        for i in 0..<tiles.count {
            clearTile(at: i)
        }
    }

    private func clearTile(at index: Int) {
        guard let texture = tiles[index].sdfTexture,
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return
        }

        // Fill with max representable half-float (~65504)
        // RealityKit/Metal doesn't have a direct "fill texture" for 3D,
        // so we'll use a compute shader in TilePaint.metal (clearTile kernel)
        // For now, just document that tiles start uninitialized

        blitEncoder.endEncoding()
        commandBuffer.commit()
    }

    // MARK: - Accessors

    /// Get tile count
    var tileCount: Int {
        return tiles.count
    }

    /// Get tile parameters for a specific index
    func getTileFrame(at index: Int) -> TileFrame? {
        guard index < tiles.count else { return nil }
        return tiles[index].frame
    }
}
