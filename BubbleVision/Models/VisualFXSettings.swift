import Foundation

/// Bitmask-driven configuration for modular visual effects.
struct VisualFXSettings: Codable {
    static let colorShift: UInt8 = 1 << 0
    static let vignette: UInt8 = 1 << 1
    static let chromaticAberration: UInt8 = 1 << 2
    static let scanlines: UInt8 = 1 << 3
    static let glitch: UInt8 = 1 << 4
    static let edgeGlow: UInt8 = 1 << 5
    static let noise: UInt8 = 1 << 6

    var enabled: Bool
    var effectsMask: UInt8
    var intensity: Float
    var param2: Float
    var param3: Float

    static let `default` = VisualFXSettings(
        enabled: true,
        effectsMask: vignette | edgeGlow,
        intensity: 0.6,
        param2: 0.4,
        param3: 0.2
    )

    mutating func toggleEffect(_ flag: UInt8) {
        effectsMask ^= flag
    }
}

