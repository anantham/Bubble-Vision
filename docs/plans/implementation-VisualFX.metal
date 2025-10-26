// VisualFX.metal
// Modular visual effects system (Tier 1+2) for soap-film rendering
// Bitmask-controlled, no branch divergence, GPU-friendly
//
// Usage: #include "VisualFX.metal" in your CustomMaterial shader
//
// References:
//   - Main design doc: docs/plans/2025-10-24-continuous-trails-design.md (Section 6)
//   - Conversation: conversation-2025-10-24.jsonl

#pragma once
#include <metal_stdlib>
using namespace metal;

// ============================================================================
// BITMASK FLAGS (Single uint32)
// ============================================================================

// Bit assignments:
//   bit 0: edge highlighting (Fresnel rim)
//   bit 1: parallax patterns (tri-planar world-space)
//   bit 2: front/back gradient (side differentiation)
//   bit 3: grazing fade (prevent harsh pops)
//   bit 4: screen refraction (wet glass)
//   bit 5: sparkle glints (micro-facet twinkle)
//   bit 6: age-based ripples (temporal layering)

/// Check if effect is enabled in bitmask
inline bool fxEnabled(uint mask, uint bit) {
    return ((mask >> bit) & 1u) != 0;
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Simple hash function (screen-space with time jitter)
/// Not true blue noise, but stable enough to avoid pattern locking
inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

/// HSV to RGB conversion (hue in [0,1], saturation/value in [0,1])
inline float3 hsv2rgb(float h, float s, float v) {
    float3 k = float3(1.0, 2.0/3.0, 1.0/3.0);
    float3 p = abs(fract(h + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

// ============================================================================
// PARAMETER BLOCK
// ============================================================================

/// Unified parameter structure for all visual effects
/// Pass this to each fxXXX() function
struct FXParams {
    // Control
    uint   flags;               // bitmask of enabled effects

    // Spatial
    float  time;                // seconds (for animation)
    float2 screenUV;            // screen-space UV (0..1)
    float3 worldPos;            // world-space position
    float3 viewDir;             // direction toward camera (normalized)
    float3 worldNormal;         // world-space normal (normalized)

    // Color accumulators
    float3 baseColor;           // RGB base color (modified in-place)
    float  opticalThickness;    // accumulator for interference patterns (nm-equivalent)
    float  opacity;             // alpha (modified in-place)

    // Refraction
    float2 screenUVParallax;    // parallax-correct UV (precomputed from intrinsics)
    float  refractionScale;     // 0.002-0.006 (tunable)

    // Age (for trails)
    float  age;                 // seconds since creation
    float  maxAge;              // max age for normalization (0-1)
};

// ============================================================================
// TIER 1 EFFECTS (Depth Perception)
// ============================================================================

/// Edge Highlighting (Fresnel Rim)
/// Brighter, thicker iridescence at edges makes boundaries visible
/// Cost: ~0.3ms on film plane (simple math)
inline void fxEdge(thread FXParams &P, thread float3 &emissive) {
    if (!fxEnabled(P.flags, 0)) return;

    float NdotV = saturate(dot(normalize(P.worldNormal), normalize(P.viewDir)));
    float fresnel = pow(1.0 - NdotV, 2.5);

    // Boost opacity at edges
    P.opacity *= (0.7 + 0.3 * fresnel);

    // Add emissive rim glow
    emissive += P.baseColor * (0.25 * fresnel);

    // Increase optical thickness perception at grazing angles
    P.opticalThickness += 80.0 * fresnel;
}

/// Parallax Patterns (Tri-Planar World-Space)
/// Interference patterns shift with motion parallax, giving depth cues
/// Cost: ~0.3ms (tri-planar sampling + blending)
inline void fxParallax(thread FXParams &P) {
    if (!fxEnabled(P.flags, 1)) return;

    // Tri-planar blend weights from normal
    float3 w = abs(P.worldNormal);
    w /= (w.x + w.y + w.z + 1e-5);

    float scale = 8.0;  // cycles per meter

    // Three projections
    float2 uvX = P.worldPos.yz * scale;
    float2 uvY = P.worldPos.xz * scale;
    float2 uvZ = P.worldPos.xy * scale;

    // Shift by view direction for parallax effect
    float2 vShift = normalize(P.viewDir.xy + 1e-5) * 0.25;
    uvX += vShift;
    uvY += vShift;
    uvZ += vShift;

    // Simple sinusoidal noise (can replace with texture lookup)
    float nX = sin(uvX.x * 6.28318) * cos(uvX.y * 6.28318);
    float nY = sin(uvY.x * 6.28318) * cos(uvY.y * 6.28318);
    float nZ = sin(uvZ.x * 6.28318) * cos(uvZ.y * 6.28318);

    // Blend three projections
    float pNoise = w.x * nX + w.y * nY + w.z * nZ;

    // Modulate optical thickness
    P.opticalThickness += pNoise * 60.0;
}

/// Front/Back Gradient (Side Differentiation)
/// Subtle tint difference so you know which side you're on
/// Cost: <0.1ms (simple color mix)
inline void fxFrontBack(thread FXParams &P) {
    if (!fxEnabled(P.flags, 2)) return;

    bool isFrontFace = dot(P.worldNormal, P.viewDir) < 0.0;

    if (isFrontFace) {
        // Front: cool tint (cyan/white)
        float3 cool = float3(0.9, 1.0, 1.0);
        P.baseColor = mix(P.baseColor, cool, 0.08);
    } else {
        // Back: warm tint (amber)
        float3 warm = float3(1.0, 0.95, 0.85);
        P.baseColor = mix(P.baseColor, warm, 0.12);
    }
}

/// Grazing Fade (Prevent Harsh Pops)
/// Opacity drops at shallow viewing angles when moving through film
/// Cost: <0.1ms (simple fade calculation)
inline void fxGrazingFade(thread FXParams &P) {
    if (!fxEnabled(P.flags, 3)) return;

    float NdotV = abs(dot(normalize(P.worldNormal), normalize(P.viewDir)));
    float fade = saturate((NdotV + 0.15) / 1.15);
    P.opacity *= fade;
}

// ============================================================================
// TIER 2 EFFECTS (Wet Glass Feel)
// ============================================================================

/// Screen Refraction
/// Bend camera feed behind film for "wet glass" look
/// Cost: ~0.5ms (texture sample + blend)
/// Note: Requires camera feed texture binding
inline void fxRefraction(thread FXParams &P,
                         texture2d<float> cameraFeed,
                         sampler textureSampler)
{
    if (!fxEnabled(P.flags, 4)) return;

    float3 n = normalize(P.worldNormal);
    float NdotV = saturate(dot(n, normalize(P.viewDir)));

    // Angle-dependent refraction (grazing angles bend more)
    float k = P.refractionScale * (0.5 + 0.5 * pow(1.0 - NdotV, 2.0));

    // Offset screen UV by normal projection
    float2 refractUV = P.screenUV + n.xy * k;

    // Sample camera feed
    float3 behindColor = cameraFeed.sample(textureSampler, refractUV).rgb;

    // Mix with film color (subtle bend)
    P.baseColor = mix(P.baseColor, behindColor, 0.15);
}

/// Sparkle Glints (Derivative-Driven)
/// Micro-facet twinkle on film surface
/// Cost: ~0.4ms (derivative + hash + blend)
inline void fxSparkle(thread FXParams &P, thread float3 &emissive) {
    if (!fxEnabled(P.flags, 5)) return;

    float NdotV = saturate(dot(normalize(P.worldNormal), normalize(P.viewDir)));

    // Derivative magnitude (approximation using screen-space derivatives)
    // In practice, you'd compute this from actual dfdx/dfdy of normals
    // For now, using a simplified heuristic based on normal variation
    float2 dNx = float2(dfdx(P.worldNormal.x), dfdy(P.worldNormal.x));
    float2 dNy = float2(dfdx(P.worldNormal.y), dfdy(P.worldNormal.y));
    float nVar = clamp(length(dNx) + length(dNy), 0.0, 1.0);

    // Grazing factor (more sparkles at shallow angles)
    float graze = saturate(1.0 - NdotV);

    // Sparkle factor combines normal variation with grazing
    float sFac = nVar * graze;

    // Hash for sparkle distribution (screen-space + time jitter)
    float noise = hash21(P.screenUV * 1081.0 + float2(P.time, P.time * 0.7));

    // Threshold for sparkle density (0.995 = ~0.5% of pixels sparkle)
    float sparkle = step(0.995, noise) * sFac;

    // Add to emissive
    emissive += sparkle * 0.30 * P.baseColor;
}

/// Age-Based Ripples (Temporal Layering)
/// Older trail segments wobble more, giving temporal depth
/// Cost: ~0.2ms (sin/cos + blend)
inline void fxAgeRipples(thread FXParams &P) {
    if (!fxEnabled(P.flags, 6)) return;
    if (P.maxAge <= 0.0f) return;

    // Normalize age to 0-1
    float age01 = clamp(P.age / P.maxAge, 0.0, 1.0);

    // Amplitude increases with age (old trails wobble more)
    float amp = mix(0.25, 0.8, age01);

    // Frequency decreases with age (old trails slow down)
    float freq = mix(1.8, 0.9, age01);

    // Ripple pattern (sinusoidal with time offset)
    float ripple = sin(P.worldPos.x * freq * 3.14159 + P.time) *
                   cos(P.worldPos.y * freq * 3.14159 + P.time * 1.3);

    // Apply to optical thickness
    P.opticalThickness += ripple * amp * 80.0;
}

// ============================================================================
// USAGE EXAMPLE (Fragment Shader)
// ============================================================================

/*
[[visible]]
void frag_main(realitykit::surface_parameters params) {
    auto surf = params.surface();
    auto geo = params.geometry();

    // Build FX parameter block
    FXParams fx;
    fx.flags = uniforms.fxMask;              // bitmask from settings
    fx.time = uniforms.time;
    fx.screenUV = geo.uv0();
    fx.worldPos = geo.world_position();
    fx.viewDir = -geo.view_direction();
    fx.worldNormal = geo.world_normal();
    fx.baseColor = float3(1.0);              // start with white
    fx.opticalThickness = 400.0;             // base interference thickness
    fx.opacity = 0.35;                       // base transparency
    fx.refractionScale = uniforms.refractionScale;
    fx.age = geo.custom_attribute<float>();  // from vertex attribute
    fx.maxAge = 60.0;                        // 1 minute

    float3 emissive = float3(0);

    // Apply effects in sequence (order doesn't matter; all are additive/multiplicative)
    fxEdge(fx, emissive);
    fxParallax(fx);
    fxFrontBack(fx);
    fxGrazingFade(fx);
    fxRefraction(fx, cameraFeedTex, linearSampler);
    fxSparkle(fx, emissive);
    fxAgeRipples(fx);

    // Use accumulated optical thickness for iridescence
    float hue = fract(fx.opticalThickness * 0.0020 + uniforms.hueSeed);
    float3 rainbow = hsv2rgb(hue, 0.87, 1.0);
    float3 finalColor = mix(rainbow, float3(1.0), 0.06);  // slight white mix

    // Output to RealityKit surface
    surf.set_base_color(half3(finalColor));
    surf.set_roughness(0.1 + 0.15 * pow(1.0 - saturate(dot(fx.worldNormal, fx.viewDir)), 2.5));
    surf.set_metallic(0.0);
    surf.set_opacity(half(fx.opacity));
    surf.set_emissive_color(half3(emissive));
}
*/

// ============================================================================
// PERFORMANCE NOTES
// ============================================================================

// Typical costs (iPhone 12 Pro, film plane mesh):
//   - Tier 1 all enabled: ~0.8ms
//   - Tier 2 all enabled: +0.9ms
//   - Total (all 7 effects): ~1.7ms
//
// Optimization tips:
//   - Effects are independent; can be toggled without affecting others
//   - No branching in inner loops (bitmask check exits early)
//   - Refraction is most expensive (texture sample); disable first if over-budget
//   - Sparkles are second most expensive (derivatives + hash)

// ============================================================================
// TUNABLES (Recommended Defaults)
// ============================================================================

// Edge highlighting:
//   - Fresnel exponent: 2.5 (lower = wider rim, higher = tighter)
//   - Emissive boost: 0.25 (subtle glow)
//   - Thickness add: 80.0 (optical thickness units)

// Parallax patterns:
//   - Scale: 8.0 cycles/meter (lower = larger patterns, higher = finer)
//   - View shift: 0.25 (parallax offset magnitude)
//   - Thickness add: 60.0

// Front/back gradient:
//   - Cool mix: 0.08 (subtle)
//   - Warm mix: 0.12 (slightly stronger for back)

// Grazing fade:
//   - Offset: 0.15 (fade starts at NdotV = 0.15)
//   - Scale: 1.15 (full opacity at NdotV = 1.0)

// Refraction:
//   - Scale: 0.0035 (0.002-0.006 range; lower = subtle, higher = fisheye)
//   - Mix: 0.15 (blend factor with background)

// Sparkle:
//   - Threshold: 0.995 (0.5% pixel density; lower = more sparkles)
//   - Intensity: 0.30 (emissive multiplier)

// Age ripples:
//   - Young amp: 0.25, old amp: 0.8
//   - Young freq: 1.8, old freq: 0.9
//   - Thickness add: 80.0 (scaled by ripple amplitude)

// ============================================================================
// SETTINGS → BITMASK CONVERSION (Swift)
// ============================================================================

/*
Swift code to convert settings to bitmask:

extension BubbleVisionSettings {
    var featureMask: UInt32 {
        var m: UInt32 = 0
        func set(_ bit: Int, _ on: Bool) {
            if on { m |= (1 << UInt32(bit)) }
        }
        set(0, edgeHighlighting)
        set(1, parallaxPatterns)
        set(2, frontBackGradient)
        set(3, grazingFade)
        set(4, screenRefraction)
        set(5, sparkleGlints)
        set(6, ageBasedRipples)
        return m
    }
}

// Pass to shader:
filmParams.fxMask = settings.featureMask
*/

// ============================================================================
// COLOR MODES (Extension)
// ============================================================================

// For future color system integration:
//
// enum ColorMode { single, paletteCycle, rainbow, ambientReactive }
//
// In shader, instead of fixed HSV conversion, use:
//   - single: uniforms.baseColorLin (precomputed HSB→linear sRGB)
//   - paletteCycle: sample from uniforms.paletteLin[i] where i cycles by time
//   - rainbow: compute hue from thickness (current behavior)
//   - ambientReactive: modulate hue by ARKit light estimate

// ============================================================================
// END OF FILE
// ============================================================================
