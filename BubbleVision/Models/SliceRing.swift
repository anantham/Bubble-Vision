import Foundation
import simd

/// GPU-friendly description of a trail slice with stable local frame.
/// Size is 96 bytes (aligned for Metal buffer uploads).
struct SliceRing: Codable {
    var id: UUID
    var position: SIMD3<Float>
    var tangent: SIMD3<Float>
    var normal: SIMD3<Float>
    var binormal: SIMD3<Float>
    var radius: Float
    var timestamp: TimeInterval
    var prevPrevIdx: Int32
    var prevIdx: Int32
    var nextIdx: Int32
    var nextNextIdx: Int32

    init(id: UUID = UUID(),
         position: SIMD3<Float>,
         tangent: SIMD3<Float>,
         normal: SIMD3<Float>,
         binormal: SIMD3<Float>,
         radius: Float = 0.15,
         timestamp: TimeInterval = Date().timeIntervalSince1970,
         prevPrevIdx: Int32 = -1,
         prevIdx: Int32 = -1,
         nextIdx: Int32 = -1,
         nextNextIdx: Int32 = -1) {
        self.id = id
        self.position = position
        self.tangent = tangent
        self.normal = normal
        self.binormal = binormal
        self.radius = radius
        self.timestamp = timestamp
        self.prevPrevIdx = prevPrevIdx
        self.prevIdx = prevIdx
        self.nextIdx = nextIdx
        self.nextNextIdx = nextNextIdx
    }
}

/// Maintains a ring buffer of trail slices, computing stable bases via parallel transport.
final class SliceRingBuffer {
    private(set) var slices: [SliceRing] = []
    private let maxSlices = 1_024

    /// Add a slice positioned at `position`, returning the created entry.
    @discardableResult
    func addSlice(position: SIMD3<Float>, timestamp: TimeInterval = Date().timeIntervalSince1970, radius: Float = 0.15) -> SliceRing {
        let basis = computeBasis(for: position, timestamp: timestamp)
        var slice = SliceRing(position: position,
                              tangent: basis.tangent,
                              normal: basis.normal,
                              binormal: basis.binormal,
                              radius: radius,
                              timestamp: timestamp)

        let newIndex = Int32(slices.count)
        if slices.count >= 1 {
            slice.prevIdx = newIndex - 1
            slices[slices.count - 1].nextIdx = newIndex
        }
        if slices.count >= 2 {
            slice.prevPrevIdx = newIndex - 2
            slices[slices.count - 2].nextNextIdx = newIndex
        }

        slices.append(slice)
        clampIfNeeded()
        return slice
    }

    func clear() {
        slices.removeAll()
    }

    func getAllSlices() -> [SliceRing] {
        slices
    }

    private func clampIfNeeded() {
        guard slices.count > maxSlices else { return }
        let overflow = slices.count - maxSlices
        slices.removeFirst(overflow)

        for i in slices.indices {
            var entry = slices[i]
            entry.prevPrevIdx = adjust(index: entry.prevPrevIdx, by: overflow)
            entry.prevIdx = adjust(index: entry.prevIdx, by: overflow)
            entry.nextIdx = adjust(index: entry.nextIdx, by: overflow)
            entry.nextNextIdx = adjust(index: entry.nextNextIdx, by: overflow)
            slices[i] = entry
        }
    }

    private func adjust(index: Int32, by offset: Int) -> Int32 {
        guard index >= 0 else { return -1 }
        let value = Int(index) - offset
        return value >= 0 ? Int32(value) : -1
    }

    private func computeBasis(for position: SIMD3<Float>, timestamp: TimeInterval) -> (tangent: SIMD3<Float>, normal: SIMD3<Float>, binormal: SIMD3<Float>) {
        guard let last = slices.last else {
            let tangent = SIMD3<Float>(0, 0, -1)
            let normal = SIMD3<Float>(0, 1, 0)
            let binormal = simd_normalize(simd_cross(tangent, normal))
            return (tangent, normal, binormal)
        }

        var tangent = position - last.position
        let distance = simd_length(tangent)
        if distance < 1e-5 {
            return (last.tangent, last.normal, last.binormal)
        }

        tangent /= distance
        let previousTangent = simd_normalize(last.tangent)

        let rotationAxis = simd_cross(previousTangent, tangent)
        let axisLength = simd_length(rotationAxis)

        var normal: SIMD3<Float>
        if axisLength < 1e-5 {
            normal = last.normal
        } else {
            let axis = rotationAxis / axisLength
            let angle = asin(max(min(axisLength, 1.0), -1.0))
            let quaternion = simd_quatf(angle: angle, axis: axis)
            normal = quaternion.act(last.normal)
        }

        if simd_length_squared(normal) < 1e-6 {
            let fallback = abs(tangent.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            normal = simd_normalize(simd_cross(fallback, tangent))
        }

        var binormal = simd_normalize(simd_cross(tangent, normal))
        normal = simd_normalize(simd_cross(binormal, tangent))

        if !normal.allFinite || !binormal.allFinite {
            normal = last.normal
            binormal = last.binormal
        }

        return (tangent, normal, binormal)
    }
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool {
        return isFinite(x) && isFinite(y) && isFinite(z)
    }

    private func isFinite(_ value: Float) -> Bool {
        value.isFinite
    }
}
