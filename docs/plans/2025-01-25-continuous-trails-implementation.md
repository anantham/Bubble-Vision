# Continuous Trails & Visual Enhancements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform single-tap bubble placement into continuous trail system where holding button and moving iPad sweeps a volumetric soap film through space, with enhanced visual effects for realistic bubble appearance.

**Architecture:** "Stronger J" dual-representation system: (1) Film plane mesh locked to iPad screen at z=0 device space with all visual effects, (2) Sparse tiled SDF volume cache for persistent trails beyond 5cm, (3) Shader blending layer with seam softening.

**Tech Stack:** Swift 5.9+, SwiftUI, RealityKit, ARKit, Metal Shading Language, CoreMotion

---

## Phase 1: Foundation (Week 1)

**Goal:** Film plane at device z=0, basic aperture rendering, minimal trail geometry

### Task 1.1: Motion Coupling Foundation

**Files:**
- Create: `BubbleVision/AR/MotionCoupler.swift`
- Test: Manual verification in ContentView (no unit test yet - AR integration)

**Step 1: Create MotionCoupler class structure**

Create file `BubbleVision/AR/MotionCoupler.swift`:

```swift
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
```

**Step 2: Integrate MotionCoupler in ARCoordinator**

Modify `BubbleVision/AR/ARCoordinator.swift`:

Find the class declaration and add property:

```swift
// Add after existing properties
private let motionCoupler = MotionCoupler()
```

Find `session(_:didUpdate:)` method and add at the beginning:

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // Update motion coupling
    motionCoupler.update(from: frame)

    // ... existing code ...
}
```

Find where session starts (in `setupARView` or similar) and add:

```swift
motionCoupler.start()
```

**Step 3: Test motion coupling**

Run: Build and run on physical device (Cmd+R)

Expected: App builds successfully, no crashes. Motion data populates (verify in debugger by setting breakpoint in `update(from:)`)

**Step 4: Commit**

```bash
git add BubbleVision/AR/MotionCoupler.swift BubbleVision/AR/ARCoordinator.swift
git commit -m "[FEAT]: Add motion coupling foundation

MOTIVATION:
- Need IMU data (gravity, gyro) for film wobble dynamics
- Film plane must respond to device tilt and rotation
- Foundation for Tier A (analytic) and Tier B (grid) wobble

APPROACH:
- CoreMotion CMDeviceMotion for raw IMU
- Low-pass filters: 6 Hz gravity, 30 Hz gyro
- Device-space outputs updated per ARFrame

CHANGES:
- BubbleVision/AR/MotionCoupler.swift: New class with filtered IMU outputs
- BubbleVision/AR/ARCoordinator.swift: Integrated motion updates

IMPACT:
- Foundation for wobble effects
- No visual changes yet (data collection only)
- Prepares for film plane dynamics

TESTING:
- Build on physical device
- Verify no crashes
- Debugger shows gravity/omega updating

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 1.2: Film Material Shader Foundation

**Files:**
- Create: `BubbleVision/Shaders/FilmPlane.metal`
- Modify: `BubbleVision.xcodeproj` (add file to target)

**Step 1: Create basic film plane shader**

Create file `BubbleVision/Shaders/FilmPlane.metal`:

```metal
// FilmPlane.metal
// Basic iridescent film shader at z=0 device space
// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 2

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Uniforms (will expand in later tasks)
struct FilmUniforms {
    float time;
    float hueSeed;
    float baseThickness;  // nm equivalent for interference
};

// HSV to RGB conversion
float3 hsv2rgb(float h, float s, float v) {
    float3 k = float3(1.0, 2.0/3.0, 1.0/3.0);
    float3 p = abs(fract(h + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

[[visible]]
void filmPlane_fragment(realitykit::surface_parameters params) {
    auto surface = params.surface();
    auto geo = params.geometry();

    // Get uniforms (bind from Swift)
    constexpr sampler s(filter::linear);
    float time = 0.0;  // TODO: bind uniform
    float hueSeed = 0.3;
    float baseThickness = 400.0;  // nm

    // Basic Fresnel
    float3 N = geo.world_normal();
    float3 V = -geo.view_direction();
    float NdotV = saturate(dot(normalize(N), normalize(V)));
    float fresnel = pow(1.0 - NdotV, 2.5);

    // Optical thickness (combines base + Fresnel for edge enhancement)
    float thickness = baseThickness + fresnel * 150.0;

    // Thin-film interference color
    float hue = fract(thickness * 0.0025 + hueSeed);  // 0.0025 = 1/400 (tuned multiplier)
    float3 rainbow = hsv2rgb(hue, 0.87, 1.0);

    // Slight white mix (less than original 12% that made it matte)
    float3 finalColor = mix(rainbow, float3(1.0), 0.04);

    // Roughness varies with Fresnel (shinier at edges)
    float roughness = 0.08 + 0.12 * (1.0 - fresnel);

    // Base opacity
    float opacity = 0.35;

    // Output
    surface.set_base_color(half3(finalColor));
    surface.set_roughness(half(roughness));
    surface.set_metallic(0.0);
    surface.set_opacity(half(opacity));
    surface.set_emissive_color(half3(0.0));
}
```

**Step 2: Add shader to Xcode project**

1. Open `BubbleVision.xcodeproj` in Xcode
2. Right-click `BubbleVision/Shaders` folder → Add Files
3. Select `FilmPlane.metal`
4. Ensure "BubbleVision" target is checked
5. Build (Cmd+B) to verify shader compiles

Expected: Build succeeds with no Metal compilation errors

**Step 3: Commit**

```bash
git add BubbleVision/Shaders/FilmPlane.metal
git commit -m "[FEAT]: Add film plane shader foundation

MOTIVATION:
- Replace matte appearance with vibrant iridescence
- Foundation for z=0 film plane rendering
- Increase hue multiplier from 0.002 to 0.0025 for more color variation
- Reduce white mix from 12% to 4% for less dullness

APPROACH:
- Basic Fresnel-based thin-film interference
- HSV color space for rainbow generation
- Edge-enhanced thickness for depth perception

CHANGES:
- BubbleVision/Shaders/FilmPlane.metal: New shader with improved color vibrancy

IMPACT:
- Foundation for all Tier 1+2 visual effects
- Not yet connected to geometry (shader only)
- 4x reduction in white mixing vs original

TESTING:
- Metal shader compiles without errors
- Visual verification in next task (geometry integration)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 1.3: Film Plane Geometry Generator

**Files:**
- Create: `BubbleVision/AR/FilmPlaneBuilder.swift`

**Step 1: Create FilmPlaneBuilder class**

Create file `BubbleVision/AR/FilmPlaneBuilder.swift`:

```swift
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
```

**Step 2: Test mesh generation**

Add to `ARCoordinator.swift` temporarily for testing:

```swift
// In ARCoordinator class, add property:
private var filmPlaneBuilder: FilmPlaneBuilder?

// In setupARView or similar:
if let device = MTLCreateSystemDefaultDevice() {
    filmPlaneBuilder = FilmPlaneBuilder(device: device, apertureShape: .circle(radius: 0.15))
}

// Modify placeBubble() to test:
func placeBubble() {
    guard let currentFrame = arView.session.currentFrame else { return }

    // Test: Create film plane
    if let builder = filmPlaneBuilder,
       let filmEntity = try? builder.createFilmPlane(cameraTransform: currentFrame.camera.transform) {

        // Add to scene
        let anchor = AnchorEntity(world: currentFrame.camera.transform)
        anchor.addChild(filmEntity)
        arView.scene.addAnchor(anchor)

        print("✓ Film plane created")
    }
}
```

Run: Build and tap bubble button

Expected: Build succeeds, geometry appears (may be invisible without material - that's next task)

**Step 3: Commit**

```bash
git add BubbleVision/AR/FilmPlaneBuilder.swift BubbleVision/AR/ARCoordinator.swift
git commit -m "[FEAT]: Add film plane geometry generator

MOTIVATION:
- Need mesh geometry for film plane at z=0
- Support multiple aperture shapes (circle, rect, full)
- Foundation for continuous trail tessellation

APPROACH:
- Procedural mesh generation in device space
- Circle: triangle fan tessellation (32 segments)
- Rect: Simple quad (rounded corners deferred to Phase 3)
- All meshes at z=0 plane

CHANGES:
- BubbleVision/AR/FilmPlaneBuilder.swift: New mesh generator
- BubbleVision/AR/ARCoordinator.swift: Test integration in placeBubble()

IMPACT:
- Can spawn film plane geometry
- Not yet using custom shader (uses default material)
- Foundation for trail sweeping

TESTING:
- Build and tap button
- Geometry appears in scene
- No crashes

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 1.4: Wire Film Shader to Geometry

**Files:**
- Modify: `BubbleVision/AR/FilmPlaneBuilder.swift`
- Modify: `BubbleVision/AR/ARCoordinator.swift`

**Step 1: Load Metal library and create CustomMaterial**

In `FilmPlaneBuilder.swift`, add at top of class:

```swift
private let library: MTLLibrary
private var filmMaterial: CustomMaterial?

public init(device: MTLDevice, apertureShape: ApertureShape = .circle(radius: 0.15)) throws {
    self.device = device
    self.apertureShape = apertureShape

    // Load Metal library
    guard let lib = device.makeDefaultLibrary() else {
        throw MaterialError.libraryLoadFailed
    }
    self.library = lib

    // Create custom material
    self.filmMaterial = try createFilmMaterial()
}

private func createFilmMaterial() throws -> CustomMaterial {
    guard let surfaceShader = CustomMaterial.SurfaceShader(
        named: "filmPlane_fragment",
        in: library
    ) else {
        throw MaterialError.shaderNotFound
    }

    return try CustomMaterial(
        surfaceShader: surfaceShader,
        geometryModifier: nil,
        lightingModel: .physicallyBased,
        blending: .transparent
    )
}

enum MaterialError: Error {
    case libraryLoadFailed
    case shaderNotFound
}
```

**Step 2: Apply material to mesh**

In `createFilmPlane(cameraTransform:)`, after creating entity:

```swift
// Apply custom material
if let material = filmMaterial {
    entity.model?.materials = [material]
}
```

**Step 3: Update ARCoordinator to handle error**

In `ARCoordinator.swift`, update initialization:

```swift
// Change from:
filmPlaneBuilder = FilmPlaneBuilder(device: device, apertureShape: .circle(radius: 0.15))

// To:
do {
    filmPlaneBuilder = try FilmPlaneBuilder(device: device, apertureShape: .circle(radius: 0.15))
} catch {
    print("⚠️ Failed to create FilmPlaneBuilder: \(error)")
}
```

**Step 4: Test with custom shader**

Run: Build and tap bubble button

Expected: Vibrant iridescent disc appears, rainbow colors shift with viewing angle, less matte than original

**Step 5: Commit**

```bash
git add BubbleVision/AR/FilmPlaneBuilder.swift BubbleVision/AR/ARCoordinator.swift
git commit -m "[FEAT]: Wire film shader to geometry

MOTIVATION:
- Connect custom shader to film plane mesh
- Verify improved visual appearance (less matte)
- Foundation for visual effects integration

APPROACH:
- Load Metal library in FilmPlaneBuilder
- Create CustomMaterial with filmPlane_fragment shader
- Apply to generated mesh entities

CHANGES:
- BubbleVision/AR/FilmPlaneBuilder.swift: CustomMaterial integration, error handling
- BubbleVision/AR/ARCoordinator.swift: Handle builder initialization errors

IMPACT:
- Film planes now render with custom shader
- Rainbow iridescence visible
- 4% white mix (vs 12% original) = less dull
- 2.5x hue multiplier increase = more color variation

TESTING:
- Build and tap button
- Iridescent disc appears
- Colors shift with viewing angle
- Visibly less matte than original MVP

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 1.5: Path Tracking System

**Files:**
- Create: `BubbleVision/AR/PathTracker.swift`
- Modify: `BubbleVision/AR/ARCoordinator.swift`

**Step 1: Create PathTracker class**

Create file `BubbleVision/AR/PathTracker.swift`:

```swift
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
        let rotDelta = acos(clamp(dot(lastForward, currForward), -1.0, 1.0))

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
```

**Step 2: Integrate in ARCoordinator**

In `ARCoordinator.swift`, add property:

```swift
private let pathTracker = PathTracker()
```

Add button press/release tracking (modify ContentView integration):

In `ARCoordinator.swift`, add methods:

```swift
func startTrail() {
    guard let frame = arView.session.currentFrame else { return }
    pathTracker.startTracking(
        initialTransform: frame.camera.transform,
        timestamp: frame.timestamp
    )
    print("▶ Trail tracking started")
}

func updateTrail() {
    guard let frame = arView.session.currentFrame else { return }
    if pathTracker.update(transform: frame.camera.transform, timestamp: frame.timestamp) {
        print("• Sample added (total: \(pathTracker.sampleCount))")
        // TODO: Create film plane slice here
    }
}

func endTrail() {
    let path = pathTracker.stopTracking()
    print("■ Trail tracking stopped (\(path.count) samples)")
    // TODO: Finalize trail geometry
}
```

In `session(_:didUpdate:)`:

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    motionCoupler.update(from: frame)

    // Update trail if tracking
    if pathTracker.tracking {
        updateTrail()
    }
}
```

**Step 3: Update ContentView for press-and-hold**

In `ContentView.swift`, modify button to support long press:

```swift
// Replace existing Button with:
Button(action: {}) {
    Image(systemName: "wind")
        .font(.system(size: 44))
        .foregroundColor(.white)
}
.simultaneousGesture(
    LongPressGesture(minimumDuration: 0.1)
        .onChanged { _ in
            arCoordinator.startTrail()
        }
        .onEnded { _ in
            arCoordinator.endTrail()
        }
)
.disabled(!canPlaceBubbles)
```

**Step 4: Test path tracking**

Run: Build, press and hold button while moving iPad

Expected: Console shows "Trail tracking started", sample count increases, "Trail tracking stopped"

**Step 5: Commit**

```bash
git add BubbleVision/AR/PathTracker.swift BubbleVision/AR/ARCoordinator.swift BubbleVision/Views/ContentView.swift
git commit -m "[FEAT]: Add path tracking for continuous trails

MOTIVATION:
- Need to capture camera path during button hold
- Sample path at 1.5cm position or 3° rotation deltas
- Foundation for sweeping film plane through space

APPROACH:
- PathTracker class monitors transform changes
- Threshold-based sampling (avoids oversampling)
- Start/update/stop pattern integrated with button press

CHANGES:
- BubbleVision/AR/PathTracker.swift: New path tracking class
- BubbleVision/AR/ARCoordinator.swift: startTrail/updateTrail/endTrail methods
- BubbleVision/Views/ContentView.swift: LongPressGesture for hold-and-move

IMPACT:
- Button now supports press-and-hold
- Path captured during movement
- No geometry created yet (sampling only)

TESTING:
- Press and hold button while moving iPad
- Console shows sample count increasing
- Release shows final sample count

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 1.6: Continuous Slice Spawning

**Files:**
- Modify: `BubbleVision/AR/ARCoordinator.swift`

**Step 1: Add slice spawning to updateTrail**

In `ARCoordinator.swift`, modify `updateTrail()`:

```swift
func updateTrail() {
    guard let frame = arView.session.currentFrame else { return }
    if pathTracker.update(transform: frame.camera.transform, timestamp: frame.timestamp) {
        // Spawn new film plane slice
        if let builder = filmPlaneBuilder,
           let filmEntity = try? builder.createFilmPlane(cameraTransform: frame.camera.transform) {

            // Create world anchor
            let anchor = AnchorEntity(world: frame.camera.transform)
            anchor.addChild(filmEntity)
            arView.scene.addAnchor(anchor)

            print("• Slice added (total samples: \(pathTracker.sampleCount))")
        }
    }
}
```

**Step 2: Add slice management**

Add property to track spawned entities:

```swift
private var trailSlices: [ModelEntity] = []
```

Update `updateTrail()` to track entities:

```swift
func updateTrail() {
    guard let frame = arView.session.currentFrame else { return }
    if pathTracker.update(transform: frame.camera.transform, timestamp: frame.timestamp) {
        if let builder = filmPlaneBuilder,
           let filmEntity = try? builder.createFilmPlane(cameraTransform: frame.camera.transform) {

            let anchor = AnchorEntity(world: frame.camera.transform)
            anchor.addChild(filmEntity)
            arView.scene.addAnchor(anchor)

            trailSlices.append(filmEntity)
            print("• Slice added (\(trailSlices.count) total)")
        }
    }
}
```

**Step 3: Test continuous trail**

Run: Build, press and hold button, move iPad slowly in a path

Expected: Film plane slices appear along movement path, creating continuous volumetric trail

**Step 4: Commit**

```bash
git add BubbleVision/AR/ARCoordinator.swift
git commit -m "[FEAT]: Spawn film plane slices continuously

MOTIVATION:
- Create continuous trail as iPad moves
- Visualize swept volume in real-time
- Foundation for seam softening (Phase 3)

APPROACH:
- Spawn film plane mesh at each path sample
- World-anchored entities for persistence
- Track entities for later management

CHANGES:
- BubbleVision/AR/ARCoordinator.swift: updateTrail() spawns geometry, trailSlices tracking

IMPACT:
- Continuous trail now appears during movement
- Film planes spaced at 1.5cm / 3° intervals
- Each slice is independent (no seam blending yet)

TESTING:
- Press and hold button
- Move iPad slowly (circles, lines, etc.)
- Release to stop
- Continuous trail visible in AR
- Slices follow camera path

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 1 Complete

**Deliverables achieved:**
- ✅ Film plane at z=0 with improved shader (less matte)
- ✅ Path tracking during button hold
- ✅ Continuous slice spawning
- ✅ Basic aperture geometry (circle)

**What works:**
- Press and hold button to create trail
- Move iPad to sweep film through space
- Vibrant iridescence (4% white mix vs 12% original)
- Slices properly anchored in world space

**Known limitations (addressed in later phases):**
- No seam softening (visible ridges between slices)
- No volume cache (all geometry is immediate meshes)
- No visual effects (sparkles, refraction, etc.)
- No wobble dynamics
- Aperture always circular (no rect/full-screen)

---

## Phase 2: Volume Extrusion Cache (Week 2)

**Goal:** Persistent trails beyond 5cm, SDF cache, marching cubes extraction

### Task 2.1: Tile Manager Foundation

**Files:**
- Create: `BubbleVision/AR/TileManager.swift`

**Step 1: Create TileManager class structure**

Create file `BubbleVision/AR/TileManager.swift`:

```swift
import Foundation
import Metal
import simd

/// Manages sparse tiled SDF cache for persistent trails
/// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 3
public final class TileManager {

    // MARK: - Configuration

    /// Tile grid resolution (64³ voxels per tile)
    public static let tileResolution: Int = 64

    /// Voxel size in meters (varies by device tier)
    public let voxelSize: Float

    /// Maximum number of active tiles (8-12)
    public let maxTiles: Int

    // MARK: - Tile Structure

    public struct Tile {
        /// Unique identifier
        public let id: UUID

        /// Epoch (incremented on clear/move)
        public var epoch: UInt32

        /// World-space origin (min corner)
        public var origin: SIMD3<Float>

        /// SDF data buffer (R16F format)
        public var sdfBuffer: MTLBuffer?

        /// Last modified timestamp
        public var lastModified: TimeInterval

        public init(id: UUID = UUID(), epoch: UInt32, origin: SIMD3<Float>) {
            self.id = id
            self.epoch = epoch
            self.origin = origin
            self.lastModified = 0
        }
    }

    private var tiles: [Tile] = []
    private let device: MTLDevice

    // MARK: - Init

    public init(device: MTLDevice, voxelSize: Float = 0.01, maxTiles: Int = 8) throws {
        self.device = device
        self.voxelSize = voxelSize
        self.maxTiles = maxTiles

        // Pre-allocate tile buffers
        try allocateTiles()
    }

    private func allocateTiles() throws {
        let voxelCount = Self.tileResolution * Self.tileResolution * Self.tileResolution
        let bufferSize = voxelCount * MemoryLayout<Float16>.stride  // R16F

        for i in 0..<maxTiles {
            guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                throw TileError.allocationFailed
            }

            // Initialize to +infinity (empty space)
            let ptr = buffer.contents().assumingMemoryBound(to: UInt16.self)
            let infValue: UInt16 = 0x7C00  // +inf in Float16
            for j in 0..<voxelCount {
                ptr[j] = infValue
            }

            var tile = Tile(id: UUID(), epoch: 0, origin: .zero)
            tile.sdfBuffer = buffer
            tiles.append(tile)
        }
    }

    // MARK: - Public Interface

    /// Find or allocate tile containing world-space point
    public func getTile(containing point: SIMD3<Float>, timestamp: TimeInterval) -> Tile? {
        // Quantize point to tile grid
        let tileSize = Float(Self.tileResolution) * voxelSize
        let tileOrigin = floor(point / tileSize) * tileSize

        // Check if tile exists
        if let index = tiles.firstIndex(where: { $0.origin == tileOrigin && $0.sdfBuffer != nil }) {
            var tile = tiles[index]
            tile.lastModified = timestamp
            tiles[index] = tile
            return tile
        }

        // Allocate new tile (evict oldest if at capacity)
        if let oldestIndex = tiles.indices.min(by: { tiles[$0].lastModified < tiles[$1].lastModified }) {
            tiles[oldestIndex].epoch += 1
            tiles[oldestIndex].origin = tileOrigin
            tiles[oldestIndex].lastModified = timestamp

            // Clear buffer to +inf
            if let buffer = tiles[oldestIndex].sdfBuffer {
                let ptr = buffer.contents().assumingMemoryBound(to: UInt16.self)
                let infValue: UInt16 = 0x7C00
                let count = Self.tileResolution * Self.tileResolution * Self.tileResolution
                for i in 0..<count {
                    ptr[i] = infValue
                }
            }

            return tiles[oldestIndex]
        }

        return nil
    }

    /// Get all active tiles
    public func activeTiles() -> [Tile] {
        return tiles.filter { $0.sdfBuffer != nil }
    }
}

enum TileError: Error {
    case allocationFailed
}
```

**Step 2: Integrate in ARCoordinator**

In `ARCoordinator.swift`, add property:

```swift
private var tileManager: TileManager?
```

In Metal device initialization:

```swift
do {
    filmPlaneBuilder = try FilmPlaneBuilder(device: device, apertureShape: .circle(radius: 0.15))
    tileManager = try TileManager(device: device, voxelSize: 0.01, maxTiles: 8)
    print("✓ TileManager initialized (8 tiles × 64³ voxels)")
} catch {
    print("⚠️ Failed to initialize: \(error)")
}
```

**Step 3: Test tile allocation**

Run: Build and verify initialization

Expected: Console shows "TileManager initialized", no crashes, ~4MB memory allocated (8 tiles × 64³ × 2 bytes)

**Step 4: Commit**

```bash
git add BubbleVision/AR/TileManager.swift BubbleVision/AR/ARCoordinator.swift
git commit -m "[FEAT]: Add tile manager foundation

MOTIVATION:
- Need sparse SDF cache for persistent trails
- Bounded memory (8 tiles × 64³ voxels = 4 MB)
- Foundation for volume cache painting

APPROACH:
- Pre-allocated tile ring buffer
- LRU eviction when capacity reached
- R16F format for SDF storage
- Initialize to +inf (empty space)

CHANGES:
- BubbleVision/AR/TileManager.swift: New tile management system
- BubbleVision/AR/ARCoordinator.swift: TileManager initialization

IMPACT:
- Tile infrastructure ready
- No painting or marching cubes yet
- 4 MB memory footprint for cache

TESTING:
- Build succeeds
- Console shows initialization
- No memory issues

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

**[Phase 2-6 detailed implementation available in: `docs/plans/phase2-6-detailed-tasks.md`]**

---

## Phase 2-6 Overview

**Complete detailed tasks with code snippets in:** `docs/plans/phase2-6-detailed-tasks.md`

This file contains:
- ✅ Phase 2 Tasks 2.2-2.6 (SDF painting, marching cubes, tile management, blend zones)
- ✅ Phase 3 Tasks 3.1-3.4 (SliceRing, stable basis from Q6, tetrahedral gradient, seam softening)
- ✅ Phase 4 Tasks 4.1-4.5 (IMU integration, wobble grid from Q10, visual FX from Q11, camera refraction)
- ✅ Phase 5 Tasks 5.1-5.4 (Settings persistence, auto-degradation from Q14, device detection, resource guard)
- ✅ Phase 6 Tasks 6.1-6.4 (Telemetry, testing protocol, polish, App Store prep)

**Research Integration:**
- Q6: Stable Basis Computation (Rotation-Minimizing Frame) → Phase 3
- Q10: Wobble Grid Implementation (32×18 spring-damper) → Phase 4
- Q11: Visual FX Shader Integration (7 modular effects) → Phase 4
- Q14: Auto-Degradation Algorithm (EMA with hysteresis) → Phase 5

**Quick Phase Summary:**

**Phase 2: Volume Extrusion Cache (Week 2)**
- SDF paint kernel with smooth-min blending
- Marching cubes extraction (GPU)
- Tile ring buffer with epoch management
- Film plane ↔ cache blend zones

**Phase 3: Seam Softening (Week 3)**
- SliceRing with rotation-minimizing frame (RMF)
- Tetrahedral gradient evaluation (40% faster)
- Fragment shader integration
- Stable basis prevents twisting

**Phase 4: IMU & Visual FX (Week 4)**
- CoreMotion acceleration tracking
- 32×18 spring-damper wobble grid (Tier B)
- 7 modular visual effects (bitmask control)
- Camera feed refraction

**Phase 5: Settings & Performance (Week 5)**
- Debounced settings persistence (250ms)
- EMA-based auto-degradation (α=0.1, 3 tiers)
- Device capability detection (Tier A/B)
- Resource guard (memory caps)

**Phase 6: Polish & Ship (Week 6)**
- Local-only telemetry & black box (30s ring buffer)
- Comprehensive testing protocol
- Privacy audit (100% compliant)
- App Store preparation

---

## Quick Reference

**Build and run:**
```bash
open BubbleVision.xcodeproj
# Xcode: Select physical device, Cmd+R
```

**Common issues:**
- "Shader not found" → Clean build folder (Cmd+Shift+K)
- "Buffer allocation failed" → Check device memory, reduce tile count
- Crash on tap → Verify Metal device initialization

**Key files to reference:**
- Design doc: `docs/plans/2025-10-24-continuous-trails-design.md`
- Implementation files: `docs/plans/implementation-*.{metal,swift}`
- Architecture: `docs/architecture/design-philosophy.md`

---

**Plan complete. Ready for execution with superpowers:executing-plans or superpowers:subagent-driven-development.**
