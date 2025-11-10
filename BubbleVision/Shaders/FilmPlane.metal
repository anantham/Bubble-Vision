// FilmPlane.metal
// Basic iridescent film shader at z=0 device space
// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 2

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "VisualEffects.metal"
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

    float2 uv = geo.uv0();

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

    // Blend against camera distance for film plane.
    float3 worldPos = geo.world_position();
    float4 viewPos = params.uniforms().world_to_view() * float4(worldPos, 1.0);
    float distFromCamera = length(viewPos.xyz / max(viewPos.w, 1e-5));
    float blendFactor = smoothstep(0.5, 0.7, distFromCamera);  // 50-70cm transition
    float baseOpacityScale = mix(1.0, 1.0 - blendFactor, 1.0);

    // Retrieve packed FX/seam parameters.
    float4 fxParams = params.uniforms().custom_parameter();
    uint packedMask = uint(fxParams.x + 0.5);
    const uint seamBit = 1u << 7;
    bool seamEnabled = (packedMask & seamBit) != 0;
    uint mask = packedMask & (seamBit - 1u);
    float fxIntensity = fxParams.y;
    float fxParam2 = fxParams.z;
    float fxParam3 = fxParams.w;

    // Seam softening: fade rim and lift roughness when slices overlap.
    float seamStrength = seamEnabled ? 1.0 : 0.0;
    float edgeBlend = smoothstep(0.35, 0.5, length(uv - float2(0.5)));
    float seamFactor = seamStrength * edgeBlend;
    float roughnessBoost = seamFactor * 0.22;
    roughness = clamp(roughness + roughnessBoost, 0.0, 1.0);
    float seamOpacityScale = mix(1.0, 1.0 - seamFactor * 0.75, seamStrength);
    float opacityScale = baseOpacityScale * seamOpacityScale;
    finalColor = mix(finalColor, mix(finalColor, float3(1.0), 0.1), seamFactor * 0.4);

    if (mask != 0) {
        finalColor = apply_visual_effects(finalColor,
                                          uv,
                                          fresnel,
                                          mask,
                                          fxIntensity,
                                          fxParam2,
                                          fxParam3);
    }

    // Output
    surface.set_base_color(half3(finalColor));
    surface.set_roughness(half(roughness));
    surface.set_metallic(0.0);
    surface.set_opacity(half(opacity * opacityScale));
    surface.set_emissive_color(half3(0.0));
}
