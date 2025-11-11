import Foundation
import RealityKit
import Metal
import simd

/// Wraps the RealityKit CustomMaterial used by the film plane so we have a single place to configure shader inputs.
/// Matches the design doc's intent while operating within RealityKit's custom parameter limits.
///
/// **Custom Parameter Layout (SIMD4<Float>):**
/// - `x`: Packed bitmask (UInt32 as Float)
///   - Bit 7: Seam softening enable (1 = on, 0 = off)
///   - Bits 0-6: Visual FX mask (7 modular effects)
/// - `y`: Wobble intensity (0.0 = none, 1.0 = full, range: 0.0-2.0)
/// - `z`: Gravity · Normal (dot product, range: -1.0 to 1.0)
/// - `w`: Device tier / profile (0 = Tier A, 1 = Tier B, 2 = Tier C)
final class FilmMaterial {

    // MARK: - FX Packing Constants

    /// Bit positions in the FX bitmask (bits 0-6)
    enum FXBit: UInt32 {
        case sparkles = 0        // Bit 0: Sparkle highlights
        case chromatic = 1       // Bit 1: Chromatic aberration
        case refraction = 2      // Bit 2: Camera feed refraction
        case rimGlow = 3         // Bit 3: Edge rim glow
        case dustMotes = 4       // Bit 4: Dust particle overlay
        case haloBloom = 5       // Bit 5: Halo bloom effect
        case microRipples = 6    // Bit 6: Micro surface ripples
        // Bit 7: Reserved for seam softening (set separately)
    }

    /// Device performance tier (maps to custom_parameter.w)
    enum DeviceTier: Float {
        case tierA = 0.0  // High-end (iPhone 14 Pro+, iPad Pro M2)
        case tierB = 1.0  // Mid-tier (iPhone 13, iPad Air)
        case tierC = 2.0  // Low-end (iPhone 11, older devices)
    }

    struct FXState {
        var mask: UInt32 = 0              // Visual FX bitmask (bits 0-6)
        var wobbleIntensity: Float = 0.5  // Wobble strength (0.0-2.0)
        var gravityDotNormal: Float = 0   // Gravity modulation (-1.0 to 1.0)
        var deviceTier: DeviceTier = .tierB

        /// Enable or disable specific FX bit
        mutating func setFX(_ bit: FXBit, enabled: Bool) {
            if enabled {
                mask |= (1 << bit.rawValue)
            } else {
                mask &= ~(1 << bit.rawValue)
            }
        }

        /// Check if FX bit is enabled
        func isFXEnabled(_ bit: FXBit) -> Bool {
            return (mask & (1 << bit.rawValue)) != 0
        }
    }

    private let template: CustomMaterial
    private var fxState = FXState()
    private var wobbleTexture: TextureResource?

    init(device: MTLDevice, library: MTLLibrary) throws {
        let surfaceShader = CustomMaterial.SurfaceShader(
            named: "filmPlane_fragment",
            in: library
        )

        let geometryModifier = CustomMaterial.GeometryModifier(
            named: "wobbleDisplacement_geometry",
            in: library
        )

        var material = try CustomMaterial(
            surfaceShader: surfaceShader,
            geometryModifier: geometryModifier,
            lightingModel: .lit
        )
        material.custom.value = SIMD4<Float>(0, 0, 0, 0)
        self.template = material
    }

    /// Returns a copy of the template material configured for the specified camera position and seam state.
    func material(cameraPosition: SIMD3<Float>, seamEnabled: Bool) -> CustomMaterial {
        var material = template

        // Analytic wobble doesn't need texture, but keep for legacy/dev mode
        if let wobbleTexture {
            material.custom.texture = CustomMaterial.Texture(wobbleTexture)
        } else {
            material.custom.texture = nil
        }

        // Pack parameters according to documented layout
        let seamBit: UInt32 = seamEnabled ? (1 << 7) : 0
        let packedMask = seamBit | fxState.mask

        material.custom.value = SIMD4<Float>(
            Float(packedMask),              // x: FX bitmask + seam bit
            fxState.wobbleIntensity,        // y: wobble intensity
            fxState.gravityDotNormal,       // z: gravity modulation
            fxState.deviceTier.rawValue     // w: device tier
        )

        return material
    }

    func setFXState(_ state: FXState) {
        fxState = state
    }

    func setWobbleTexture(_ texture: TextureResource?) {
        wobbleTexture = texture
    }

    /// Unconfigured base material (used for shared references).
    var baseMaterial: CustomMaterial {
        template
    }
}
