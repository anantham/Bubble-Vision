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

    /// Smoothed lateral acceleration derived from IMU user acceleration.
    public private(set) var accelSmoothed2D: SIMD2<Float> = .zero

    /// Instantaneous acceleration magnitude for jolt detection.
    public private(set) var joltMagnitude: Float = 0

    // MARK: - Private State

    private let motionManager = CMMotionManager()
    private var isActive = false

    // Low-pass filters (60 Hz → 6 Hz for gravity, 30 Hz for gyro)
    private let gravityAlpha: Float = 0.1  // ~6 Hz cutoff at 60 Hz
    private let gyroAlpha: Float = 0.5     // ~30 Hz cutoff at 60 Hz

    private var gravityFiltered: SIMD3<Float> = SIMD3(0, -1, 0)
    private var omegaFiltered: SIMD3<Float> = .zero

    // Acceleration tracking
    private var accelHistory: [SIMD3<Float>] = []
    private let historySize = 10  // ~0.16s at 60 Hz

    // Jolt detection
    private var lastJoltTime: TimeInterval = 0
    private let joltCooldown: TimeInterval = 0.3

    // Camera motion tracking
    private var lastCameraPosition: SIMD3<Float>?
    private var lastCameraTimestamp: TimeInterval?

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

        // Track user acceleration (gravity-compensated)
        let accel = SIMD3<Float>(
            Float(motion.userAcceleration.x),
            Float(motion.userAcceleration.y),
            Float(motion.userAcceleration.z)
        )

        accelHistory.append(accel)
        if accelHistory.count > historySize {
            accelHistory.removeFirst()
        }

        if !accelHistory.isEmpty {
            let sum = accelHistory.reduce(SIMD3<Float>.zero, +)
            let smoothed = sum / Float(accelHistory.count)
            accelSmoothed2D = SIMD2<Float>(smoothed.x, smoothed.y)
        } else {
            accelSmoothed2D = .zero
        }

        joltMagnitude = simd_length(accel)

        // Tangent velocity from camera pose delta
        let cameraPosition = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )

        if let previousPosition = lastCameraPosition,
           let previousTimestamp = lastCameraTimestamp {
            let dt = Float(frame.timestamp - previousTimestamp)
            if dt > 0 {
                let delta = cameraPosition - previousPosition
                let lateral = SIMD2<Float>(delta.x, delta.y) / dt
                velTangent2D = lateral
            }
        }

        lastCameraPosition = cameraPosition
        lastCameraTimestamp = frame.timestamp
    }

    /// Detect sudden acceleration spike (jolt).
    func detectJolt(threshold: Float = 1.5) -> Bool {
        let now = Date().timeIntervalSince1970
        guard now - lastJoltTime > joltCooldown else { return false }

        if joltMagnitude > threshold {
            lastJoltTime = now
            return true
        }

        return false
    }
}
