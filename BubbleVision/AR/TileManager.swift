import Foundation
import Metal
import simd

/// Tile coordinate frame metadata for the sparse SDF cache.
/// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 3
struct TileFrame {
    var originWS: SIMD3<Float>      // World-space origin
    var axisWS: simd_float3x3       // Columns = X, Y, Z (orthonormal)
    var voxelSize: Float            // Meters per voxel
    var dim: Int32                  // 64 (voxels per side)
    var epoch: UInt32               // Incremented when repositioned
}

/// Single tile in the sparse cache. Holds frame info and 3D texture storage.
struct Tile {
    var frame: TileFrame
    var sdfTexture: MTLTexture?     // 3D R16Float texture (64³)
}

/// Manages sparse tiled SDF cache for persistent trails.
/// Initializes a small grid of tiles that can later be repurposed as the user moves.
final class TileManager {
    private let device: MTLDevice
    private(set) var tiles: [Tile] = []

    // Defaults (can be tuned per device tier in future tasks)
    private let defaultTileCount = 8            // Start with 8 tiles
    private let defaultDim: Int32 = 64          // 64³ voxels per tile
    private let defaultVoxelSize: Float = 0.02  // 2 cm per voxel → 1.28 m tile extent

    private lazy var commandQueue: MTLCommandQueue? = device.makeCommandQueue()
    private lazy var defaultLibrary: MTLLibrary? = device.makeDefaultLibrary()
    private lazy var paintPipeline: MTLComputePipelineState? = {
        guard let function = defaultLibrary?.makeFunction(name: "paintSweptSegment") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()
    private lazy var clearPipeline: MTLComputePipelineState? = {
        guard let function = defaultLibrary?.makeFunction(name: "clearTile") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()
    private lazy var marchingCubesPipeline: MTLComputePipelineState? = {
        guard let function = defaultLibrary?.makeFunction(name: "marchingCubesTile") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()

    private let maxVertexCount = 120_000
    private var cameraLastPosition: SIMD3<Float>?
    private let tileFollowDistance: Float = 1.5
    private let tileRepositionThreshold: Float = 3.0
    private let gridStride: Float = 1.5

    init(device: MTLDevice, tileCount: Int = 8) {
        self.device = device
        allocateTiles(count: tileCount)
    }

    // MARK: - Initialization

    private func allocateTiles(count: Int) {
        tiles.reserveCapacity(count)

        for i in 0..<count {
            // Position tiles in a rough grid around origin so early paints have coverage.
            let gridX = Float((i % 4) - 2)  // -2, -1, 0, 1
            let gridZ = Float((i / 4) - 1)  // -1, 0, 1

            let frame = TileFrame(
                originWS: SIMD3<Float>(gridX * 1.5, 0, gridZ * 1.5),  // 1.5 m spacing
                axisWS: matrix_identity_float3x3,                     // World-aligned basis
                voxelSize: defaultVoxelSize,
                dim: defaultDim,
                epoch: 0
            )

            var tile = Tile(frame: frame, sdfTexture: nil)

            let descriptor = MTLTextureDescriptor()
            descriptor.width = Int(defaultDim)
            descriptor.height = Int(defaultDim)
            descriptor.depth = Int(defaultDim)
            descriptor.pixelFormat = .r16Float
            descriptor.textureType = .type3D
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private  // GPU-only for best performance

            tile.sdfTexture = device.makeTexture(descriptor: descriptor)

            tiles.append(tile)

            print("✓ Allocated tile \(i): origin=\(frame.originWS), extent=\(defaultVoxelSize * Float(defaultDim))m")
        }

        clearAllTiles()
    }

    private func clearAllTiles() {
        for index in tiles.indices {
            clearTile(at: index)
        }
        cameraLastPosition = nil
    }

    private func clearTile(at index: Int) {
        guard let texture = tiles[index].sdfTexture,
              let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = clearPipeline else {
            return
        }

        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(texture, index: 0)

        var tileParams = tiles[index].frame
        computeEncoder.setBytes(&tileParams, length: MemoryLayout<TileFrame>.stride, index: 0)

        let dim = Int(tiles[index].frame.dim)
        let gridSize = MTLSize(width: dim, height: dim, depth: dim)
        let threadsPerThreadgroup = MTLSize(width: 4, height: 4, depth: 4)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)

        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - Accessors

    /// Total number of allocated tiles.
    var tileCount: Int {
        tiles.count
    }

    /// Retrieve frame metadata for the specified tile.
    func getTileFrame(at index: Int) -> TileFrame? {
        guard tiles.indices.contains(index) else { return nil }
        return tiles[index].frame
    }

    /// Update tile positions to follow the camera. Returns indices of tiles that moved.
    @discardableResult
    public func updateTilePositions(cameraPosition: SIMD3<Float>) -> [Int] {
        if cameraLastPosition == nil {
            cameraLastPosition = cameraPosition
            return []
        }

        guard let last = cameraLastPosition else { return [] }
        let delta = simd_length(cameraPosition - last)
        guard delta > tileFollowDistance else { return [] }

        cameraLastPosition = cameraPosition

        guard !tiles.isEmpty else { return [] }

        var farthestIndex = -1
        var maxDistance: Float = -Float.greatestFiniteMagnitude

        for (index, tile) in tiles.enumerated() {
            let tileExtent = tile.frame.voxelSize * Float(tile.frame.dim)
            let halfExtent = SIMD3<Float>(repeating: tileExtent * 0.5)
            let center = tile.frame.originWS + tile.frame.axisWS * halfExtent
            let distance = simd_length(center - cameraPosition)
            if distance > maxDistance {
                maxDistance = distance
                farthestIndex = index
            }
        }

        guard farthestIndex >= 0, maxDistance > tileRepositionThreshold else { return [] }

        repositionTile(at: farthestIndex, near: cameraPosition)
        return [farthestIndex]
    }

    // MARK: - Painting

    /// Paint a swept segment into every tile using the GPU compute kernel.
    public func paintSegment(
        from P0: SIMD3<Float>,
        to P1: SIMD3<Float>,
        aperture: FilmPlaneBuilder.ApertureShape,
        cameraTransform: simd_float4x4
    ) {
        guard let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = paintPipeline else {
            return
        }

        computeEncoder.setComputePipelineState(pipeline)

        let right = SIMD3<Float>(cameraTransform.columns.0.x,
                                 cameraTransform.columns.0.y,
                                 cameraTransform.columns.0.z)
        let up = SIMD3<Float>(cameraTransform.columns.1.x,
                              cameraTransform.columns.1.y,
                              cameraTransform.columns.1.z)
        let forward = SIMD3<Float>(cameraTransform.columns.2.x,
                                   cameraTransform.columns.2.y,
                                   cameraTransform.columns.2.z)

        let stampParameters = buildStampParams(
            from: P0,
            to: P1,
            aperture: aperture,
            right: right,
            up: up,
            forward: forward
        )

        var stamp = stampParameters
        computeEncoder.setBytes(&stamp, length: MemoryLayout<SegmentStampParams>.stride, index: 1)

        for index in tiles.indices {
            guard let texture = tiles[index].sdfTexture else { continue }

            computeEncoder.setTexture(texture, index: 0)

            var tileParams = tiles[index].frame
            computeEncoder.setBytes(&tileParams, length: MemoryLayout<TileFrame>.stride, index: 0)

            let dim = Int(tileParams.dim)
            let gridSize = MTLSize(width: dim, height: dim, depth: dim)
            let threadsPerThreadgroup = MTLSize(width: 4, height: 4, depth: 4)
            computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
        }

        computeEncoder.endEncoding()
        commandBuffer.commit()
    }

    private func buildStampParams(
        from P0: SIMD3<Float>,
        to P1: SIMD3<Float>,
        aperture: FilmPlaneBuilder.ApertureShape,
        right: SIMD3<Float>,
        up: SIMD3<Float>,
        forward: SIMD3<Float>
    ) -> SegmentStampParams {
        let axis = simd_float3x3(columns: (
            simd_normalize(right),
            simd_normalize(up),
            simd_normalize(forward)
        ))

        var halfExtents = SIMD2<Float>(repeating: 0.15)  // default circle radius
        var cornerRadius: Float = 0.0
        var shapeType: UInt32 = 0  // 0 = circle, 1 = rounded rect

        switch aperture {
        case .circle(let radius):
            halfExtents = SIMD2<Float>(repeating: radius)
            shapeType = 0
        case .roundedRect(let width, let height, let radius):
            halfExtents = SIMD2<Float>(width * 0.5, height * 0.5)
            cornerRadius = radius
            shapeType = 1
        case .fullScreen:
            // Approximate the iPad screen dimensions (matches FilmPlaneBuilder default)
            halfExtents = SIMD2<Float>(0.25 * 0.5, 0.18 * 0.5)
            cornerRadius = 0.01
            shapeType = 1
        }

        return SegmentStampParams(
            P0: P0,
            P1: P1,
            axisWS: axis,
            halfExtents: halfExtents,
            cornerRadius: cornerRadius,
            thickness: 0.004,
            smoothK: 0.4,
            shapeType: shapeType,
            padding: SIMD3<UInt32>(repeating: 0)
        )
    }

    private func gridOffset(for index: Int) -> SIMD3<Float> {
        let columns = 4
        let row = index / columns
        let col = index % columns
        let offsetX = Float(col - 2) * gridStride
        let offsetZ = Float(row - 1) * gridStride
        return SIMD3<Float>(offsetX, 0, offsetZ)
    }

    private func repositionTile(at index: Int, near cameraPosition: SIMD3<Float>) {
        guard tiles.indices.contains(index) else { return }

        var tile = tiles[index]
        tile.frame.epoch &+= 1

        let offset = gridOffset(for: index)
        let tileExtent = tile.frame.voxelSize * Float(tile.frame.dim)
        let halfExtent = SIMD3<Float>(repeating: tileExtent * 0.5)

        let desiredCenter = SIMD3<Float>(
            cameraPosition.x + offset.x,
            cameraPosition.y,
            cameraPosition.z + offset.z
        )

        let unalignedOrigin = desiredCenter - halfExtent
        let voxelSize = tile.frame.voxelSize
        let alignedOrigin = (unalignedOrigin / voxelSize).rounded(.down) * voxelSize

        tile.frame.originWS = alignedOrigin
        tiles[index] = tile

        clearTile(at: index)

        print("♻️ Repositioned tile \(index) to \(alignedOrigin), epoch=\(tile.frame.epoch)")
    }

    // MARK: - Mesh Extraction

    public struct Vertex {
        public var position: SIMD3<Float>
        public var normal: SIMD3<Float>
        public var uv: SIMD2<Float>

        public init(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) {
            self.position = position
            self.normal = normal
            self.uv = uv
        }
    }

    /// Extract mesh from a tile using GPU marching cubes.
    public func extractMesh(from tileIndex: Int) -> (vertices: [Vertex], indices: [UInt32], frame: TileFrame)? {
        guard tiles.indices.contains(tileIndex),
              let texture = tiles[tileIndex].sdfTexture,
              let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = marchingCubesPipeline else {
            return nil
        }

        let vertexBufferLength = maxVertexCount * MemoryLayout<Vertex>.stride
        let indexBufferLength = maxVertexCount * MemoryLayout<UInt32>.stride
        let counterBufferLength = MemoryLayout<UInt32>.stride * 2

        guard let vertexBuffer = device.makeBuffer(length: vertexBufferLength, options: .storageModeShared),
              let indexBuffer = device.makeBuffer(length: indexBufferLength, options: .storageModeShared),
              let counterBuffer = device.makeBuffer(length: counterBufferLength, options: .storageModeShared) else {
            return nil
        }

        let counters = counterBuffer.contents().bindMemory(to: UInt32.self, capacity: 2)
        counters[0] = 0
        counters[1] = 0

        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: 1)

        var frame = tiles[tileIndex].frame
        computeEncoder.setBytes(&frame, length: MemoryLayout<TileFrame>.stride, index: 2)
        computeEncoder.setBuffer(counterBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(counterBuffer, offset: MemoryLayout<UInt32>.stride, index: 4)

        let dim = max(Int(frame.dim) - 1, 1)
        let gridSize = MTLSize(width: dim, height: dim, depth: dim)
        let threadsPerThreadgroup = MTLSize(width: 4, height: 4, depth: 4)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)

        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let vertCount = Int(min(counters[0], UInt32(maxVertexCount)))
        guard vertCount > 0 else { return nil }

        let vertexPointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: vertCount)
        let indexPointer = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: vertCount)

        let vertices = Array(UnsafeBufferPointer(start: vertexPointer, count: vertCount))
        let indices = Array(UnsafeBufferPointer(start: indexPointer, count: vertCount))

        return (vertices, indices, frame)
    }
}

// Struct passed to Metal compute kernel. Must match layout in TilePaint.metal.
private struct SegmentStampParams {
    var P0: SIMD3<Float>
    var P1: SIMD3<Float>
    var axisWS: simd_float3x3
    var halfExtents: SIMD2<Float>
    var cornerRadius: Float
    var thickness: Float
    var smoothK: Float
    var shapeType: UInt32
    var padding: SIMD3<UInt32>
}
