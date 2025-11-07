import Foundation
import Metal
import simd

/// CPU-based spring-damper simulation that produces a displacement texture for wobble effects.
final class WobbleGrid {
    private let width = 32
    private let height = 18

    private let stiffness: Float = 50.0
    private let damping: Float = 10.0
    private let restLengthX: Float
    private let restLengthY: Float

    private var positions: [SIMD2<Float>]
    private var velocities: [SIMD2<Float>]

    private let device: MTLDevice
    private(set) var displacementTexture: MTLTexture?

    init?(device: MTLDevice, gridSpan: Float = 1.0) {
        self.device = device

        let count = width * height
        positions = Array(repeating: .zero, count: count)
        velocities = Array(repeating: .zero, count: count)

        restLengthX = gridSpan / Float(width - 1)
        restLengthY = gridSpan / Float(height - 1)

        guard createDisplacementTexture() else {
            return nil
        }
    }

    private func createDisplacementTexture() -> Bool {
        let descriptor = MTLTextureDescriptor()
        descriptor.width = width
        descriptor.height = height
        descriptor.pixelFormat = .rg32Float
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        displacementTexture = device.makeTexture(descriptor: descriptor)
        return displacementTexture != nil
    }

    /// Advance the simulation by `dt` seconds, applying the supplied lateral acceleration.
    func update(dt: Float, externalAcceleration: SIMD2<Float>) {
        // Apply external acceleration to all nodes.
        for index in positions.indices {
            velocities[index] += externalAcceleration * dt
        }

        var forces = Array(repeating: SIMD2<Float>.zero, count: positions.count)

        // Interior nodes only (edges remain anchored).
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x

                applySpring(from: index, to: index - 1, restLength: restLengthX, forces: &forces) // left
                applySpring(from: index, to: index + 1, restLength: restLengthX, forces: &forces) // right
                applySpring(from: index, to: index - width, restLength: restLengthY, forces: &forces) // up
                applySpring(from: index, to: index + width, restLength: restLengthY, forces: &forces) // down
            }
        }

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                velocities[index] += forces[index] * dt
                positions[index] += velocities[index] * dt
                velocities[index] *= 0.99
            }
        }

        uploadDisplacement()
    }

    private func applySpring(from origin: Int, to neighbour: Int, restLength: Float, forces: inout [SIMD2<Float>]) {
        let delta = positions[neighbour] - positions[origin]
        let distance = simd_length(delta)
        guard distance > .ulpOfOne else { return }

        let direction = delta / distance
        let stretch = distance - restLength
        let springForce = stiffness * stretch * direction
        let relativeVelocity = velocities[neighbour] - velocities[origin]
        let dampingForce = damping * relativeVelocity
        forces[origin] += springForce + dampingForce
    }

    private func uploadDisplacement() {
        guard let texture = displacementTexture else { return }

        var pixelBuffer = [Float](repeating: 0, count: width * height * 2)
        for index in positions.indices {
            pixelBuffer[index * 2] = positions[index].x
            pixelBuffer[index * 2 + 1] = positions[index].y
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        pixelBuffer.withUnsafeBytes { rawBuffer in
            texture.replace(region: region,
                            mipmapLevel: 0,
                            withBytes: rawBuffer.baseAddress!,
                            bytesPerRow: width * MemoryLayout<Float>.stride * 2)
        }
    }

    func reset() {
        positions = Array(repeating: .zero, count: positions.count)
        velocities = Array(repeating: .zero, count: velocities.count)
        uploadDisplacement()
    }
}

