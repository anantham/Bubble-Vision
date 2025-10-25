import Foundation
import RealityKit
import Metal
import ARKit

/// Generates film plane mesh at z=0 device space
/// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 2.2
public final class FilmPlaneBuilder {

    // MARK: - Configuration

    public enum ApertureShape {
        case circle(radius: Float)
        case roundedRect(width: Float, height: Float, cornerRadius: Float)
        case fullScreen
    }

    private let device: MTLDevice
    private let apertureShape: ApertureShape

    // MARK: - Init

    public init(device: MTLDevice, apertureShape: ApertureShape = .circle(radius: 0.15)) {
        self.device = device
        self.apertureShape = apertureShape
    }

    // MARK: - Mesh Generation

    /// Create film plane mesh in device space at z=0
    /// - Parameter cameraTransform: ARCamera transform (to position in world)
    /// - Returns: ModelEntity with film plane mesh
    public func createFilmPlane(cameraTransform: simd_float4x4) throws -> ModelEntity {
        let mesh = try generateMesh()

        // Create entity
        let entity = ModelEntity(mesh: mesh)

        // Position at camera with z=0 offset (device space)
        // Film plane IS the screen, so it's at the camera position
        entity.transform = Transform(matrix: cameraTransform)

        return entity
    }

    // MARK: - Private Helpers

    private func generateMesh() throws -> MeshResource {
        switch apertureShape {
        case .circle(let radius):
            return try generateCircleMesh(radius: radius)
        case .roundedRect(let w, let h, let r):
            return try generateRoundedRectMesh(width: w, height: h, cornerRadius: r)
        case .fullScreen:
            return try generateFullScreenMesh()
        }
    }

    private func generateCircleMesh(radius: Float) throws -> MeshResource {
        // Simple tessellated circle in XY plane (z=0)
        let segments = 32
        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0)]  // center
        var normals: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 1)]
        var uvs: [SIMD2<Float>] = [SIMD2<Float>(0.5, 0.5)]
        var indices: [UInt32] = []

        // Generate circle vertices
        for i in 0...segments {
            let angle = Float(i) * (2.0 * .pi / Float(segments))
            let x = cos(angle) * radius
            let y = sin(angle) * radius

            positions.append(SIMD3<Float>(x, y, 0))
            normals.append(SIMD3<Float>(0, 0, 1))

            let u = 0.5 + 0.5 * cos(angle)
            let v = 0.5 + 0.5 * sin(angle)
            uvs.append(SIMD2<Float>(u, v))
        }

        // Generate triangle fan indices
        for i in 0..<segments {
            indices.append(0)
            indices.append(UInt32(i + 1))
            indices.append(UInt32(i + 2))
        }

        // Build mesh descriptor
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    private func generateRoundedRectMesh(width: Float, height: Float, cornerRadius: Float) throws -> MeshResource {
        // Simplified: Use plane for now (proper rounded rect in Phase 3)
        let w = width / 2.0
        let h = height / 2.0

        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(-w, -h, 0),
            SIMD3<Float>( w, -h, 0),
            SIMD3<Float>( w,  h, 0),
            SIMD3<Float>(-w,  h, 0)
        ]

        let normals: [SIMD3<Float>] = Array(repeating: SIMD3<Float>(0, 0, 1), count: 4)

        let uvs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 1)
        ]

        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    private func generateFullScreenMesh() throws -> MeshResource {
        // Full iPad screen dimensions (approximate for now)
        return try generateRoundedRectMesh(width: 0.25, height: 0.18, cornerRadius: 0.01)
    }
}
