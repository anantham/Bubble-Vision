//
// VisualEffects.metal
// Phase 4: Modular visual FX system with 7 bitmask-controlled effects
// Reference: FilmMaterial.FXBit enum
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Utility Functions

[[maybe_unused]] static inline float3 fx_hsv2rgb(float h, float s, float v) {
    float3 k = float3(1.0, 2.0/3.0, 1.0/3.0);
    float3 p = abs(fract(h + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

// Hash function for procedural noise
static inline float fx_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Value noise
static inline float fx_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = fx_hash(i + float2(0.0, 0.0));
    float b = fx_hash(i + float2(1.0, 0.0));
    float c = fx_hash(i + float2(0.0, 1.0));
    float d = fx_hash(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// MARK: - Effect Functions

/// Bit 0: Sparkle highlights - Procedural star-like highlights
static inline float3 fx_sparkles(float3 color, float2 uv, float time, float intensity) {
    // Layered sparkle patterns
    float2 p1 = uv * 40.0 + float2(time * 0.3, 0.0);
    float2 p2 = uv * 60.0 + float2(0.0, time * 0.4);

    float sparkle1 = pow(fx_noise(p1), 8.0);
    float sparkle2 = pow(fx_noise(p2), 10.0);

    float sparkle = (sparkle1 + sparkle2 * 0.5) * intensity * 0.8;
    return color + float3(sparkle) * float3(0.9, 0.95, 1.0);
}

/// Bit 1: Chromatic aberration - RGB channel shift
static inline float3 fx_chromatic(float3 color, float2 uv, float fresnel, float intensity) {
    float2 center = uv - 0.5;
    float dist = length(center);

    // Radial shift based on fresnel and distance from center
    float shift = fresnel * dist * intensity * 0.015;

    float3 aberration;
    aberration.r = color.r;  // Red channel (no shift)
    aberration.g = mix(color.g, color.r, shift * 0.5);  // Green shift
    aberration.b = mix(color.b, color.g, shift);  // Blue shift

    return aberration;
}

/// Bit 2: Camera feed refraction - Placeholder (requires camera texture)
static inline float3 fx_refraction(float3 color, float2 uv, float fresnel, float intensity) {
    // Simulate refraction distortion without actual camera feed
    float2 offset = normalize(uv - 0.5) * fresnel * intensity * 0.02;
    // Would sample camera texture here if available
    // For now, just add subtle color shift to simulate
    float3 shifted = color * (1.0 + float3(offset.x, offset.y, -offset.x) * 0.3);
    return mix(color, shifted, intensity * 0.5);
}

/// Bit 3: Rim glow - Enhanced edge illumination
static inline float3 fx_rim_glow(float3 color, float fresnel, float intensity) {
    float rim = pow(fresnel, 2.5) * intensity;
    float3 glowColor = float3(0.8, 0.9, 1.0);  // Soft blue-white glow
    return color + rim * glowColor * 0.4;
}

/// Bit 4: Dust motes - Floating particle overlay
static inline float3 fx_dust_motes(float3 color, float2 uv, float time, float intensity) {
    // Multiple layers of slowly moving particles
    float2 p1 = uv * 30.0 + float2(time * 0.05, time * 0.08);
    float2 p2 = uv * 45.0 + float2(-time * 0.07, time * 0.06);
    float2 p3 = uv * 60.0 + float2(time * 0.04, -time * 0.09);

    float mote1 = smoothstep(0.92, 0.98, fx_noise(p1));
    float mote2 = smoothstep(0.94, 0.99, fx_noise(p2));
    float mote3 = smoothstep(0.96, 1.0, fx_noise(p3));

    float motes = (mote1 + mote2 * 0.7 + mote3 * 0.5) * intensity * 0.3;
    return color + float3(motes) * float3(0.95, 0.97, 1.0);
}

/// Bit 5: Halo bloom - Soft diffuse glow
static inline float3 fx_halo_bloom(float3 color, float2 uv, float fresnel, float intensity) {
    float2 center = uv - 0.5;
    float dist = length(center);

    // Radial bloom from edges
    float bloom = (1.0 - dist) * fresnel * intensity * 0.5;
    bloom = pow(bloom, 1.5);

    float3 bloomColor = color * 1.3;  // Brighter version of base color
    return mix(color, bloomColor, bloom);
}

/// Bit 6: Micro ripples - Surface tension effect
static inline float3 fx_micro_ripples(float3 color, float2 uv, float time, float intensity) {
    // High-frequency ripple patterns
    float2 p = uv * 80.0;
    float ripple1 = sin(p.x * 6.28 + time * 2.0) * 0.5 + 0.5;
    float ripple2 = sin(p.y * 6.28 + time * 1.7 + 1.5) * 0.5 + 0.5;

    float ripple = (ripple1 * ripple2) * intensity * 0.15;

    // Modulate color and add slight iridescence
    float3 rippleColor = fx_hsv2rgb(ripple * 0.1, 0.3, 1.0);
    return color * (1.0 + rippleColor * ripple);
}

// MARK: - Main Effect Application

/// Apply all enabled visual effects based on bitmask
/// Phase 4: Uses wobbleIntensity and gravityDotNormal parameters
[[maybe_unused]] static inline float3 apply_visual_effects(
    float3 color,
    float2 uv,
    float fresnel,
    uint mask,
    float wobbleIntensity,
    float gravityDotNormal,
    float deviceTier
) {
    if (mask == 0) { return color; }

    // Use deviceTier to scale effects (Tier A=full, Tier C=reduced)
    float tierScale = 1.0 - (deviceTier * 0.15);  // A=1.0, B=0.85, C=0.7

    // Simulate time using position-based seed (no uniforms.time() available)
    float time = fract(dot(uv * 1000.0, float2(0.129898, 0.78233))) * 100.0;

    // Bit 0: Sparkles
    if (mask & (1u << 0)) {
        color = fx_sparkles(color, uv, time, wobbleIntensity * tierScale);
    }

    // Bit 1: Chromatic aberration
    if (mask & (1u << 1)) {
        color = fx_chromatic(color, uv, fresnel, wobbleIntensity * tierScale);
    }

    // Bit 2: Camera refraction
    if (mask & (1u << 2)) {
        color = fx_refraction(color, uv, fresnel, wobbleIntensity * 0.8 * tierScale);
    }

    // Bit 3: Rim glow
    if (mask & (1u << 3)) {
        color = fx_rim_glow(color, fresnel, wobbleIntensity * tierScale);
    }

    // Bit 4: Dust motes
    if (mask & (1u << 4)) {
        color = fx_dust_motes(color, uv, time, wobbleIntensity * 0.6 * tierScale);
    }

    // Bit 5: Halo bloom
    if (mask & (1u << 5)) {
        color = fx_halo_bloom(color, uv, fresnel, wobbleIntensity * tierScale);
    }

    // Bit 6: Micro ripples
    if (mask & (1u << 6)) {
        color = fx_micro_ripples(color, uv, time, wobbleIntensity * tierScale);
    }

    return saturate(color);
}
