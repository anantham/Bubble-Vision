//
// VisualEffects.metal
// Helper routines for modular surface effects driven by bitmask flags.
//

#include <metal_stdlib>
using namespace metal;

[[maybe_unused]] static inline float3 fx_hsv2rgb(float h, float s, float v) {
    float3 k = float3(1.0, 2.0/3.0, 1.0/3.0);
    float3 p = abs(fract(h + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

static inline float3 fx_color_shift(float3 color, float amount) {
    float maxC = max(max(color.r, color.g), color.b);
    float minC = min(min(color.r, color.g), color.b);
    float delta = maxC - minC;
    if (delta < 1e-5) { return color; }

    float hue = 0.0;
    if (maxC == color.r) {
        hue = fmod(((color.g - color.b) / delta), 6.0);
    } else if (maxC == color.g) {
        hue = ((color.b - color.r) / delta) + 2.0;
    } else {
        hue = ((color.r - color.g) / delta) + 4.0;
    }
    hue = fract(hue / 6.0 + amount);

    float saturation = delta / maxC;
    float value = maxC;
    return fx_hsv2rgb(hue, saturation, value);
}

static inline float3 fx_vignette(float3 color, float2 uv, float strength) {
    float2 center = uv - 0.5;
    float dist = length(center) * 1.6;
    float vignette = smoothstep(1.0, 0.2, dist);
    return mix(color, color * vignette, clamp(strength, 0.0, 1.0));
}

static inline float3 fx_edge_glow(float3 color, float fresnel, float intensity) {
    float glow = pow(fresnel, 2.0) * intensity;
    return color + glow * float3(0.7, 0.8, 1.0);
}

static inline float3 fx_noise(float3 color, float2 uv, float intensity) {
    float n = fract(sin(dot(uv * 2048.0, float2(12.9898, 78.233))) * 43758.5453);
    return mix(color, color * (0.8 + 0.2 * n), intensity);
}

[[maybe_unused]] static inline float3 apply_visual_effects(float3 color,
                                                           float2 uv,
                                                           float fresnel,
                                                           uint mask,
                                                           float intensity,
                                                           float param2,
                                                           float param3) {
    if (mask == 0) { return color; }

    if (mask & (1u << 0)) {
        color = fx_color_shift(color, intensity * 0.1);
    }
    if (mask & (1u << 1)) {
        color = fx_vignette(color, uv, intensity);
    }
    if (mask & (1u << 5)) {
        color = fx_edge_glow(color, fresnel, param2);
    }
    if (mask & (1u << 6)) {
        color = fx_noise(color, uv, param3);
    }

    return saturate(color);
}
