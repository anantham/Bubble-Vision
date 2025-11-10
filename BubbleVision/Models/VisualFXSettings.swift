import Foundation

/// Bitmask-driven configuration for modular visual effects (Phase 4).
/// Maps to FilmMaterial.FXBit enum and VisualEffects.metal implementations.
struct VisualFXSettings: Codable {
    // Phase 4: Updated to match FilmMaterial.FXBit enum
    static let sparkles: UInt8 = 1 << 0            // Bit 0: Sparkle highlights
    static let chromatic: UInt8 = 1 << 1           // Bit 1: Chromatic aberration
    static let refraction: UInt8 = 1 << 2          // Bit 2: Camera feed refraction
    static let rimGlow: UInt8 = 1 << 3             // Bit 3: Edge rim glow
    static let dustMotes: UInt8 = 1 << 4           // Bit 4: Dust particle overlay
    static let haloBloom: UInt8 = 1 << 5           // Bit 5: Halo bloom effect
    static let microRipples: UInt8 = 1 << 6        // Bit 6: Micro surface ripples

    var enabled: Bool
    var effectsMask: UInt8

    // Note: intensity, param2, param3 deprecated in favor of Phase 4 params
    // Keep for backward compatibility with saved settings
    var intensity: Float
    var param2: Float
    var param3: Float

    static let `default` = VisualFXSettings(
        enabled: false,  // Disabled by default for performance
        effectsMask: 0,  // No effects enabled initially
        intensity: 0.5,
        param2: 0.0,
        param3: 0.0
    )

    mutating func toggleEffect(_ flag: UInt8) {
        effectsMask ^= flag
    }
}

