import Foundation
import ARKit
import CoreMotion
import simd

/// Transforms device motion (IMU) into film dynamics parameters
/// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 4
public final class MotionCoupler {
    // MARK: - Public Outputs (Device Space)

    /// Gravity direction in device space (normalized, pointing down)
    public private(set) var gravityDS: SIMD3<Float> = SIMD3(0, -1, 0)

    /// Angular velocity in device space (rad/s)
    public private(set) var omegaDS: SIMD3<Float> = .zero

    /// Tangent velocity magnitude (m/s) - lateral motion
    public private(set) var velTangent2D: SIMD2<Float> = .zero

    // MARK: - Private State

    private let motionManager = CMMotionManager()
    private var isActive = false

    // Low-pass filters (60 Hz → 6 Hz for gravity, 30 Hz for gyro)
    private let gravityAlpha: Float = 0.1  // ~6 Hz cutoff at 60 Hz
    private let gyroAlpha: Float = 0.5     // ~30 Hz cutoff at 60 Hz

    private var gravityFiltered: SIMD3<Float> = SIMD3(0, -1, 0)
    private var omegaFiltered: SIMD3<Float> = .zero

    // MARK: - Lifecycle

    public init() {
        // Motion manager configured on start()
    }

    deinit {
        stop()
    }

    // MARK: - Control

    /// Start motion updates (call once in ARCoordinator)
    public func start() {
        guard !isActive else { return }

        guard motionManager.isDeviceMotionAvailable else {
            print("⚠️ DeviceMotion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)

        isActive = true
    }

    /// Stop motion updates
    public func stop() {
        guard isActive else { return }
        motionManager.stopDeviceMotionUpdates()
        isActive = false
    }

    // MARK: - Update (Call Every ARFrame)

    /// Update motion state from ARFrame
    /// - Parameter frame: Current ARFrame
    public func update(from frame: ARFrame) {
        guard isActive else { return }

        guard let motion = motionManager.deviceMotion else { return }

        // Raw IMU data (device space)
        let gRaw = SIMD3<Float>(
            Float(motion.gravity.x),
            Float(motion.gravity.y),
            Float(motion.gravity.z)
        )

        let wRaw = SIMD3<Float>(
            Float(motion.rotationRate.x),
            Float(motion.rotationRate.y),
            Float(motion.rotationRate.z)
        )

        // Low-pass filter
        gravityFiltered = gravityAlpha * gRaw + (1 - gravityAlpha) * gravityFiltered
        omegaFiltered = gyroAlpha * wRaw + (1 - gyroAlpha) * omegaFiltered

        // Normalize gravity
        gravityDS = normalize(gravityFiltered)
        omegaDS = omegaFiltered

        // Compute tangent velocity from camera transform
        let camTransform = frame.camera.transform
        let camPos = SIMD3<Float>(camTransform.columns.3.x, camTransform.columns.3.y, camTransform.columns.3.z)

        // Simple velocity estimation (requires previous frame tracking - placeholder for now)
        velTangent2D = .zero  // TODO: Track previous position and compute delta
    }
}
