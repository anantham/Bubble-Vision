import Foundation
import ARKit
import simd

/// Tracks camera path during button press for continuous trail generation
/// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 2.3
public final class PathTracker {

    // MARK: - Configuration

    /// Minimum position delta to create new slice (meters)
    public var minPositionDelta: Float = 0.015  // 1.5cm

    /// Minimum rotation delta to create new slice (radians)
    public var minRotationDelta: Float = 0.052  // ~3 degrees

    // MARK: - State

    public struct PathSample {
        public let transform: simd_float4x4
        public let timestamp: TimeInterval

        public init(transform: simd_float4x4, timestamp: TimeInterval) {
            self.transform = transform
            self.timestamp = timestamp
        }
    }

    private var isTracking = false
    private var samples: [PathSample] = []
    private var lastSampledTransform: simd_float4x4?

    // MARK: - Public Interface

    /// Start tracking path
    public func startTracking(initialTransform: simd_float4x4, timestamp: TimeInterval) {
        isTracking = true
        samples = [PathSample(transform: initialTransform, timestamp: timestamp)]
        lastSampledTransform = initialTransform
    }

    /// Update tracking with new camera transform
    /// - Returns: true if new sample added (exceeds thresholds)
    @discardableResult
    public func update(transform: simd_float4x4, timestamp: TimeInterval) -> Bool {
        guard isTracking else { return false }
        guard let lastTransform = lastSampledTransform else { return false }

        // Check position delta
        let lastPos = SIMD3<Float>(lastTransform.columns.3.x, lastTransform.columns.3.y, lastTransform.columns.3.z)
        let currPos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let posDelta = distance(lastPos, currPos)

        // Check rotation delta (simplified: compare forward vectors)
        let lastForward = normalize(SIMD3<Float>(lastTransform.columns.2.x, lastTransform.columns.2.y, lastTransform.columns.2.z))
        let currForward = normalize(SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
        let dotProduct = dot(lastForward, currForward)
        let clampedDot = min(max(dotProduct, -1.0 as Float), 1.0 as Float)
        let rotDelta = acos(clampedDot)

        // Add sample if either threshold exceeded
        if posDelta >= minPositionDelta || rotDelta >= minRotationDelta {
            samples.append(PathSample(transform: transform, timestamp: timestamp))
            lastSampledTransform = transform
            return true
        }

        return false
    }

    /// Stop tracking and return captured path
    public func stopTracking() -> [PathSample] {
        isTracking = false
        let result = samples
        samples = []
        lastSampledTransform = nil
        return result
    }

    /// Clear path without stopping
    public func clear() {
        samples = []
        lastSampledTransform = nil
    }

    /// Current sample count
    public var sampleCount: Int {
        return samples.count
    }

    /// Is currently tracking
    public var tracking: Bool {
        return isTracking
    }
}
