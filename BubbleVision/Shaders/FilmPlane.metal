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
static inline float3 hsv2rgb_film(float h, float s, float v) {
    float3 k = float3(1.0, 2.0/3.0, 1.0/3.0);
    float3 p = abs(fract(h + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

[[visible]]
void filmPlane_fragment(realitykit::surface_parameters params) {
    auto surface = params.surface();
    auto geo = params.geometry();

    // Get uniforms (bind from Swift)
    // Note: sampler and time will be added in Phase 4 (visual effects)
    float hueSeed = 0.3;
    float baseThickness = 400.0;  // nm

    // Basic Fresnel
    float3 N = geo.normal();
    float3 V = -geo.view_direction();
    float NdotV = saturate(dot(normalize(N), normalize(V)));
    float fresnel = pow(1.0 - NdotV, 2.5);

    // Optical thickness (combines base + Fresnel for edge enhancement)
    float thickness = baseThickness + fresnel * 150.0;

    // Thin-film interference color
    float hue = fract(thickness * 0.0025 + hueSeed);  // 0.0025 = 1/400 (tuned multiplier)
    float3 rainbow = hsv2rgb_film(hue, 0.87, 1.0);

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
