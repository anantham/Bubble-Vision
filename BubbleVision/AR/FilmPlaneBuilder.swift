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
    private let library: MTLLibrary
    private let materialWrapper: FilmMaterial

    // MARK: - Public Material Access

    /// Shared iridescent material for film plane and cache meshes.
    public private(set) var sharedMaterial: CustomMaterial?

    // MARK: - Init

    public init(device: MTLDevice, apertureShape: ApertureShape = .circle(radius: 0.15)) throws {
        self.device = device
        self.apertureShape = apertureShape

        // Load Metal library
        guard let lib = device.makeDefaultLibrary() else {
            throw MaterialError.libraryLoadFailed
        }
        self.library = lib
        self.materialWrapper = try FilmMaterial(device: device, library: lib)
        self.sharedMaterial = materialWrapper.baseMaterial
    }

    enum MaterialError: Error {
        case libraryLoadFailed
        case shaderNotFound  // Reserved for future shader validation
    }

    // MARK: - Mesh Generation

    /// Create film plane mesh in device space at z=0
    /// - Parameter cameraTransform: ARCamera transform (to position in world)
    /// - Returns: ModelEntity with film plane mesh
    public func createFilmPlane(cameraTransform: simd_float4x4) throws -> ModelEntity {
        let mesh = try generateMesh()

        // Create entity
        let entity = ModelEntity(mesh: mesh)

        // Apply custom material
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        let material = materialWrapper.material(cameraPosition: cameraPosition, seamEnabled: true)
        entity.model?.materials = [material]

        // Position at camera with z=0 offset (device space)
        // Film plane IS the screen, so it's at the camera position
        entity.transform = Transform(matrix: cameraTransform)

        return entity
    }

    // MARK: - Edge Rim Pass

    /// Create edge rim entity for crack hiding (separate ModelEntity with additive shader)
    /// - Parameter cameraTransform: ARCamera transform
    /// - Returns: Optional ModelEntity with rim geometry and additive shader
    public func createEdgeRim(cameraTransform: simd_float4x4) -> ModelEntity? {
        guard let rimMesh = try? generateRimMesh() else {
            return nil
        }

        // Create entity
        let entity = ModelEntity(mesh: rimMesh)

        // Apply rim material with additive blending
        if let rimMaterial = try? createRimMaterial() {
            entity.model?.materials = [rimMaterial]
        }

        // Position at camera (same as film plane)
        entity.transform = Transform(matrix: cameraTransform)

        return entity
    }

    private func generateRimMesh() throws -> MeshResource {
        // Thin rim geometry at edge only
        switch apertureShape {
        case .circle(let radius):
            return try generateCircleRimMesh(radius: radius)
        case .roundedRect(let w, let h, _):
            return try generateRectRimMesh(width: w, height: h)
        case .fullScreen:
            return try generateRectRimMesh(width: 0.25, height: 0.18)
        }
    }

    private func generateCircleRimMesh(radius: Float) throws -> MeshResource {
        // Very thin rim strip at outer edge
        let segments = 32
        let rimWidth: Float = 0.01  // 1cm rim width
        let innerRadius = radius - rimWidth
        let outerRadius = radius

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt32] = []

        // Generate rim vertices
        for i in 0...segments {
            let angle = Float(i) * (2.0 * .pi / Float(segments))
            let cosA = cos(angle)
            let sinA = sin(angle)

            // Inner rim vertex (less alpha)
            positions.append(SIMD3<Float>(cosA * innerRadius, sinA * innerRadius, 0))
            normals.append(SIMD3<Float>(0, 0, 1))
            let uInner = 0.5 + 0.5 * cosA * 0.9
            let vInner = 0.5 + 0.5 * sinA * 0.9
            uvs.append(SIMD2<Float>(uInner, vInner))
            colors.append(SIMD4<Float>(1, 1, 1, 0.5))

            // Outer rim vertex (full alpha)
            positions.append(SIMD3<Float>(cosA * outerRadius, sinA * outerRadius, 0))
            normals.append(SIMD3<Float>(0, 0, 1))
            let uOuter = 0.5 + 0.5 * cosA
            let vOuter = 0.5 + 0.5 * sinA
            uvs.append(SIMD2<Float>(uOuter, vOuter))
            colors.append(SIMD4<Float>(1, 1, 1, 1.0))
        }

        // Generate indices (triangle strip)
        for i in 0..<segments {
            let base = UInt32(i * 2)
            indices.append(base)
            indices.append(base + 2)
            indices.append(base + 1)

            indices.append(base + 1)
            indices.append(base + 2)
            indices.append(base + 3)
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.colors = MeshBuffer(colors)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    private func generateRectRimMesh(width: Float, height: Float) throws -> MeshResource {
        // Simplified rect rim (can enhance later)
        let rimWidth: Float = 0.01
        let w = width / 2.0
        let h = height / 2.0

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt32] = []

        // Inner rect
        let iw = w - rimWidth
        let ih = h - rimWidth

        // Outer vertices
        let outer: [SIMD3<Float>] = [
            SIMD3<Float>(-w, -h, 0), SIMD3<Float>(w, -h, 0), SIMD3<Float>(w, h, 0), SIMD3<Float>(-w, h, 0)
        ]

        // Inner vertices
        let inner: [SIMD3<Float>] = [
            SIMD3<Float>(-iw, -ih, 0), SIMD3<Float>(iw, -ih, 0), SIMD3<Float>(iw, ih, 0), SIMD3<Float>(-iw, ih, 0)
        ]

        // Build rim quad strips
        for i in 0..<4 {
            let next = (i + 1) % 4
            positions.append(inner[i])
            positions.append(outer[i])
            positions.append(inner[next])
            positions.append(outer[next])

            for _ in 0..<4 {
                normals.append(SIMD3(0, 0, 1))
            }

            colors.append(SIMD4(1, 1, 1, 0.5))
            colors.append(SIMD4(1, 1, 1, 1.0))
            colors.append(SIMD4(1, 1, 1, 0.5))
            colors.append(SIMD4(1, 1, 1, 1.0))

            let base = UInt32(i * 4)
            indices.append(base)
            indices.append(base + 1)
            indices.append(base + 2)

            indices.append(base + 2)
            indices.append(base + 1)
            indices.append(base + 3)
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.colors = MeshBuffer(colors)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    private func createRimMaterial() throws -> CustomMaterial {
        let surfaceShader = CustomMaterial.SurfaceShader(
            named: "edgeRim_fragment",
            in: library
        )

        let geometryModifier = CustomMaterial.GeometryModifier(
            named: "edgeRim_geometry",
            in: library
        )

        var material = try CustomMaterial(
            surfaceShader: surfaceShader,
            geometryModifier: geometryModifier,
            lightingModel: .unlit
        )

        // Configure for additive-like blending
        material.blending = .transparent(opacity: 1.0)

        return material
    }

    // MARK: - Material Configuration Helpers

    func updateFXState(_ state: FilmMaterial.FXState) {
        materialWrapper.setFXState(state)
    }

    func updateWobbleTexture(_ texture: TextureResource?) {
        materialWrapper.setWobbleTexture(texture)
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
        // Circle with edge band for seam softening
        let segments = 32
        let seamBandWidth: Float = 0.02  // 2cm seam band

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var alphas: [Float] = []
        var indices: [UInt32] = []

        // Center vertex (full opacity)
        positions.append(SIMD3<Float>(0, 0, 0))
        normals.append(SIMD3<Float>(0, 0, 1))
        uvs.append(SIMD2<Float>(0.5, 0.5))
        alphas.append(1.0)

        // Inner ring vertices (full opacity at 70% radius)
        let innerRadius = radius * 0.7
        for i in 0...segments {
            let angle = Float(i) * (2.0 * .pi / Float(segments))
            let x = cos(angle) * innerRadius
            let y = sin(angle) * innerRadius

            positions.append(SIMD3<Float>(x, y, 0))
            normals.append(SIMD3<Float>(0, 0, 1))

            let u = 0.5 + 0.5 * cos(angle) * 0.7
            let v = 0.5 + 0.5 * sin(angle) * 0.7
            uvs.append(SIMD2<Float>(u, v))
            alphas.append(1.0)
        }

        // Outer ring vertices (quadratic falloff)
        for i in 0...segments {
            let angle = Float(i) * (2.0 * .pi / Float(segments))
            let x = cos(angle) * radius
            let y = sin(angle) * radius

            positions.append(SIMD3<Float>(x, y, 0))
            normals.append(SIMD3<Float>(0, 0, 1))

            let u = 0.5 + 0.5 * cos(angle)
            let v = 0.5 + 0.5 * sin(angle)
            uvs.append(SIMD2<Float>(u, v))

            // Quadratic falloff: alpha = (1 - t)^2 where t ∈ [0,1]
            let t: Float = 1.0  // At outer edge, fully transparent
            let alpha = (1.0 - t) * (1.0 - t)
            alphas.append(alpha)
        }

        // Generate indices: center to inner ring
        for i in 0..<segments {
            indices.append(0)
            indices.append(UInt32(i + 1))
            indices.append(UInt32(i + 2))
        }

        // Generate indices: inner ring to outer ring (seam band)
        let innerStart = UInt32(1)
        let outerStart = UInt32(segments + 2)
        for i in 0..<segments {
            let i0 = innerStart + UInt32(i)
            let i1 = innerStart + UInt32(i + 1)
            let o0 = outerStart + UInt32(i)
            let o1 = outerStart + UInt32(i + 1)

            // Two triangles per quad
            indices.append(i0)
            indices.append(o0)
            indices.append(i1)

            indices.append(i1)
            indices.append(o0)
            indices.append(o1)
        }

        // Build mesh descriptor with vertex colors for seam alpha
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        // Use COLOR semantic for vertex alpha (pack into RGBA)
        var colors: [SIMD4<Float>] = alphas.map { SIMD4<Float>(1, 1, 1, $0) }
        descriptor.colors = MeshBuffer(colors)

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

// MARK: - MeshDescriptor helpers

fileprivate enum MeshDescriptorSemantics {
    static let vertexColor = MeshBuffers.Semantic<SIMD4<Float>>.custom(
        name: "color",
        type: SIMD4<Float>.self
    )
}

fileprivate extension MeshDescriptor {
    var colors: MeshBuffer<SIMD4<Float>>? {
        get { self[MeshDescriptorSemantics.vertexColor] }
        set { self[MeshDescriptorSemantics.vertexColor] = newValue }
    }
}
