// FilmMaterial.swift
// RealityKit CustomMaterial wrapper for film plane rendering
// Binds Swift settings to Metal shader parameters
//
// Usage: Create once, update per-frame with motion/settings
//
// References:
//   - Main design doc: docs/plans/2025-10-24-continuous-trails-design.md (Section 6)
//   - Conversation: conversation-2025-10-24.jsonl

import Foundation
import RealityKit
import Metal
import simd

// ============================================================================
// CPU PARAMETER BLOCKS (Mirror Metal Structs)
// ============================================================================

/// Film plane uniforms (matches Metal struct)
/// Important: Keep field order/types/alignment identical to Metal
struct FilmUniforms {
    // Motion coupling
    var gravity2D: SIMD2<Float> = .zero         // screen "down" direction in UV space
    var vel2D: SIMD2<Float> = .zero             // screen tangent velocity (m/s)
    var omegaMag: Float = 0                     // angular velocity magnitude (rad/s)
    var wobbleGain: Float = 1                   // 0-2 (user-adjustable)
    var time: Float = 0                         // seconds
    var _pad0: SIMD3<Float> = .zero             // padding to 16B boundary

    // Refraction + screen mapping
    var refractionScale: Float = 0.0035         // 0.002-0.006
    var _pad1: SIMD3<Float> = .zero

    // Blend thresholds (meters)
    var nearBand: Float = 0.05                  // film plane zone
    var midBand: Float = 1.5                    // cache mesh transition
    var _pad2: SIMD2<Float> = .zero

    // Aperture
    var apertureCenterUV: SIMD2<Float> = SIMD2(0.5, 0.5)
    var apertureRadiusUV: SIMD2<Float> = SIMD2(0.4, 0)  // circle: (r, 0), rect: (ax, ay)
    var apertureCornerRadius: Float = 0.05
    var apertureType: UInt32 = 0                // 0=circle, 1=roundedRect, 2=fullScreen

    // Visual FX
    var fxMask: UInt32 = 0                      // bitmask of enabled effects
    var _pad3: UInt32 = 0
}

// ============================================================================
// FILM MATERIAL WRAPPER
// ============================================================================

public final class FilmMaterial {
    // Public accessors
    public private(set) var material: CustomMaterial
    private let device: MTLDevice
    private let library: MTLLibrary

    // Dynamic resources
    private var filmUniforms = FilmUniforms()
    private var filmUniformsBuffer: MTLBuffer

    // Visual FX bitmask (see VisualFX.metal; bits 0-6)
    public var fxMask: UInt32 = 0

    // Optional wobble heightfield (Tier B)
    public var wobbleTexture: TextureResource?

    // Seam softening buffer (SliceRing*) consumed by SeamSoftener.metal
    private var sliceRingBuffer: MTLBuffer?

    // Parameter names (must match Metal argument names)
    private enum ParamName {
        static let fxMask = "fxMask"
        static let filmUniforms = "FilmUniforms"
        static let wobbleTex = "wobbleTex"
        static let sliceBuffer = "sliceBuffer"
        static let cameraFeedTex = "cameraFeedTex"
    }

    // ========================================================================
    // MARK: - Initialization
    // ========================================================================

    /// Initialize FilmMaterial with custom surface shader
    /// - Parameters:
    ///   - device: Metal device
    ///   - library: Metal library containing "frag_main" function
    ///   - lighting: Lighting model (default: physicallyBased)
    ///   - blending: Blending mode (default: transparent)
    public init(device: MTLDevice,
                library: MTLLibrary,
                lighting: CustomMaterial.LightingModel = .physicallyBased,
                blending: CustomMaterial.Blending = .transparent) throws
    {
        self.device = device
        self.library = library

        // Allocate uniforms buffer (storageModeShared for CPU write access)
        guard let buffer = device.makeBuffer(
            length: MemoryLayout<FilmUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw MaterialError.bufferAllocationFailed
        }
        self.filmUniformsBuffer = buffer

        // Compile surface shader
        let surface = try CustomMaterial.SurfaceShader(named: "frag_main", in: library)

        // Create material
        self.material = try CustomMaterial(
            surfaceShader: surface,
            geometryModifier: nil,
            lightingModel: lighting,
            blending: blending
        )

        // Bind static parameter layout
        try self.bindStaticParameterLayout()
    }

    // ========================================================================
    // MARK: - Public Setters (Per-Frame Updates)
    // ========================================================================

    /// Update FX bitmask (call when settings change)
    public func setFXMask(_ mask: UInt32) {
        self.fxMask = mask
        filmUniforms.fxMask = mask

        // Update material parameter
        if #available(iOS 15.0, *) {
            material.custom.value[ParamName.fxMask] = .uint(mask)
        } else {
            // Fallback: set individual parameters
            // (Not implemented here; would require per-flag setters)
        }
    }

    /// Set wobble texture (Tier B wobble grid)
    public func setWobbleTexture(_ tex: TextureResource?) {
        self.wobbleTexture = tex
        if let tex = tex {
            if #available(iOS 15.0, *) {
                material.custom.value[ParamName.wobbleTex] = .textureResource(tex)
            }
        }
    }

    /// Upload array of SliceRing structs for seam softening
    /// - Parameters:
    ///   - buffer: MTLBuffer containing SliceRing array (96 bytes/stride, 16B aligned)
    ///   - count: Number of SliceRing elements
    public func setSliceRings(buffer: MTLBuffer, count: Int) {
        self.sliceRingBuffer = buffer

        // Bind buffer (iOS 15+ supports named buffer binding)
        if #available(iOS 15.0, *), supportsNamedBufferBinding {
            material.custom.value[ParamName.sliceBuffer] = .buffer(buffer)
        } else {
            // Fallback: bind in render encoder (see notes below)
            // Your render callback should call:
            // encoder.setFragmentBuffer(buffer, offset: 0, index: SLICE_BUFFER_INDEX)
        }
    }

    /// Set camera feed texture for refraction
    public func setCameraFeedTexture(_ texture: MTLTexture) {
        if #available(iOS 15.0, *) {
            // Convert MTLTexture to TextureResource (requires bridging)
            // Note: RealityKit doesn't expose direct MTLTexture binding
            // Workaround: use CVMetalTexture or render to TextureResource
            // For now, documented as integration point
            // material.custom.value[ParamName.cameraFeedTex] = .texture(texture)
        }
    }

    /// Update all uniforms (call every frame)
    /// - Parameters:
    ///   - gravity2D: Screen-down direction in UV space (from MotionCoupler)
    ///   - vel2D: Screen tangent velocity in m/s
    ///   - omegaMag: Angular velocity magnitude in rad/s
    ///   - wobbleGain: Wobble intensity (0-2)
    ///   - time: Current time in seconds
    ///   - refractionScale: Refraction intensity (0.002-0.006)
    public func updateUniforms(gravity2D: SIMD2<Float>,
                               vel2D: SIMD2<Float>,
                               omegaMag: Float,
                               wobbleGain: Float,
                               time: Float,
                               refractionScale: Float = 0.0035)
    {
        filmUniforms.gravity2D = gravity2D
        filmUniforms.vel2D = vel2D
        filmUniforms.omegaMag = omegaMag
        filmUniforms.wobbleGain = wobbleGain
        filmUniforms.time = time
        filmUniforms.refractionScale = refractionScale

        // Write to shared buffer
        memcpy(filmUniformsBuffer.contents(), &filmUniforms, MemoryLayout<FilmUniforms>.stride)

        // Update material parameters
        if #available(iOS 15.0, *), supportsNamedBufferBinding {
            material.custom.value[ParamName.filmUniforms] = .buffer(filmUniformsBuffer)
        } else {
            // Fallback: set individual scalar parameters
            material.custom.value["gravity2D"] = .float2(gravity2D)
            material.custom.value["vel2D"] = .float2(vel2D)
            material.custom.value["omegaMag"] = .float(omegaMag)
            material.custom.value["wobbleGain"] = .float(wobbleGain)
            material.custom.value["time"] = .float(time)
            material.custom.value["refractionScale"] = .float(refractionScale)
        }
    }

    /// Update aperture settings
    public func updateAperture(centerUV: SIMD2<Float>,
                               radiusUV: SIMD2<Float>,
                               cornerRadius: Float,
                               type: UInt32)
    {
        filmUniforms.apertureCenterUV = centerUV
        filmUniforms.apertureRadiusUV = radiusUV
        filmUniforms.apertureCornerRadius = cornerRadius
        filmUniforms.apertureType = type

        // Update buffer
        memcpy(filmUniformsBuffer.contents(), &filmUniforms, MemoryLayout<FilmUniforms>.stride)
    }

    /// Convenience: toggle FX flags from VisualEffectSettings
    public func setFX(from settings: VisualEffectSettings) {
        var m: UInt32 = 0
        if settings.edgeHighlighting { m |= 1 << 0 }
        if settings.parallaxPatterns { m |= 1 << 1 }
        if settings.frontBackGradient { m |= 1 << 2 }
        if settings.grazingFade { m |= 1 << 3 }
        if settings.screenRefraction { m |= 1 << 4 }
        if settings.sparkleGlints { m |= 1 << 5 }
        if settings.ageBasedRipples { m |= 1 << 6 }
        setFXMask(m)
    }

    // ========================================================================
    // MARK: - Private Helpers
    // ========================================================================

    private func bindStaticParameterLayout() throws {
        // Initialize parameters so shader has valid values on first frame
        if #available(iOS 15.0, *) {
            material.custom.value[ParamName.fxMask] = .uint(fxMask)

            if supportsNamedBufferBinding {
                material.custom.value[ParamName.filmUniforms] = .buffer(filmUniformsBuffer)
            }

            if let wobbleTexture = wobbleTexture {
                material.custom.value[ParamName.wobbleTex] = .textureResource(wobbleTexture)
            }
        }
        // sliceBuffer bound when trails start (setSliceRings)
    }

    private var supportsNamedBufferBinding: Bool {
        // Feature detection: iOS 15+ supports CustomMaterial.Value.buffer()
        if #available(iOS 15.0, *) {
            return true
        }
        return false
    }
}

// ============================================================================
// MARK: - Settings Integration
// ============================================================================

/// Visual effect settings (mirrors BubbleVisionSettings subset)
public struct VisualEffectSettings {
    var edgeHighlighting: Bool = true
    var parallaxPatterns: Bool = true
    var frontBackGradient: Bool = true
    var grazingFade: Bool = true
    var screenRefraction: Bool = true
    var sparkleGlints: Bool = true
    var ageBasedRipples: Bool = true
}

// ============================================================================
// MARK: - Error Types
// ============================================================================

enum MaterialError: Error {
    case bufferAllocationFailed
    case shaderCompilationFailed
}

// ============================================================================
// INTEGRATION NOTES
// ============================================================================

/*
## Per-Frame Update Pattern

```swift
// In ARCoordinator.swift (or equivalent)
func update(frame: ARFrame) {
    // 1. Update motion coupling
    motionCoupler.update(from: frame)

    // 2. Map gravity to screen space
    let gravity2D = motionToScreenGravity2D(motionCoupler.gravityDS, cam: frame.camera)

    // 3. Update film material uniforms
    filmMaterial.updateUniforms(
        gravity2D: gravity2D,
        vel2D: motionCoupler.velTangent2D,
        omegaMag: length(motionCoupler.omegaDS),
        wobbleGain: settings.wobbleGain,
        time: Float(CACurrentMediaTime()),
        refractionScale: settings.refractionScale
    )

    // 4. Update camera feed texture (for refraction)
    if let cameraTexture = convertARFrameToCameraTexture(frame) {
        filmMaterial.setCameraFeedTexture(cameraTexture)
    }
}
```

## Camera Feed Conversion (ARKit → Metal Texture)

```swift
// Use CVMetalTextureCache for efficient conversion
var textureCache: CVMetalTextureCache?
CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)

func convertARFrameToCameraTexture(_ frame: ARFrame) -> MTLTexture? {
    let pixelBuffer = frame.capturedImage

    var texture: CVMetalTexture?
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    CVMetalTextureCacheCreateTextureFromImage(
        nil,
        textureCache!,
        pixelBuffer,
        nil,
        .bgra8Unorm,
        width, height,
        0,
        &texture
    )

    return CVMetalTextureGetTexture(texture)
}
```

## Seam Softening Buffer Upload

```swift
// When trail path updates
func updateSliceRings(_ rings: [SliceRing]) {
    let stride = MemoryLayout<SliceRing>.stride  // 96 bytes
    let bufferSize = stride * rings.count

    guard let buffer = device.makeBuffer(
        bytes: rings,
        length: bufferSize,
        options: .storageModeShared
    ) else { return }

    filmMaterial.setSliceRings(buffer: buffer, count: rings.count)
}
```

## Fallback for Older iOS (Manual Binding)

If your deployment target is iOS 14 or older, CustomMaterial doesn't support
named buffer binding. Instead, use a render callback:

```swift
// In your ARView setup
arView.scene.subscribe(to: SceneEvents.Update.self) { event in
    // Get command encoder (requires bridging to Metal)
    // This is advanced and requires direct Metal access
    // Recommend targeting iOS 15+ to avoid this complexity
}
```

For maximum compatibility, target iOS 15+ where CustomMaterial is mature.

## Wobble Grid (Tier B)

```swift
// Allocate 32×18 R16F texture
let wobbleGrid = WobbleGrid(W: 32, H: 18)
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .r16Float,
    width: wobbleGrid.W,
    height: wobbleGrid.H,
    mipmapped: false
)
descriptor.usage = [.shaderRead, .shaderWrite]

guard let texture = device.makeTexture(descriptor: descriptor) else { return }

// Update grid CPU-side (60 Hz)
wobbleGrid.step(dt: 1.0/60.0, gravity2D: gravity2D, omegaMag: omegaMag)

// Upload to GPU
let region = MTLRegionMake2D(0, 0, wobbleGrid.W, wobbleGrid.H)
let bytesPerRow = wobbleGrid.W * 2  // R16F
texture.replace(region: region, mipmapLevel: 0, withBytes: wobbleGrid.h, bytesPerRow: bytesPerRow)

// Wrap in TextureResource (iOS 15+)
if let textureResource = try? TextureResource(texture) {
    filmMaterial.setWobbleTexture(textureResource)
}
```

## Performance Monitoring

```swift
// In your debug overlay
func updateDebugStats() {
    let gpuTime = /* query from Metal */
    let filmShaderTime = /* query specific pass */

    if filmShaderTime > 2.5 {
        print("⚠️ Film shader over budget: \(filmShaderTime)ms")
    }
}
```
*/

// ============================================================================
// END OF FILE
// ============================================================================
