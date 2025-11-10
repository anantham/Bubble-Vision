//
// WobbleDisplacement.metal
// Analytic wobble geometry modifier using sum-of-sines (no texture upload needed)
// Reference: Phase 3 RealityKit-native approach
//

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

/// Analytic wobble using sum of sine waves
/// Much more efficient than texture-based approach - no CPU->GPU uploads
[[visible]]
void wobbleDisplacement_geometry(realitykit::geometry_parameters params) {
    auto geo = params.geometry();
    float2 uv = geo.uv0();
    float3 worldPos = geo.world_position();

    // Extract wobble parameters from custom_parameter
    // Layout: x=bitmask, y=wobble_intensity, z=gravity_dot_normal, w=tier
    float4 fxParams = params.uniforms().custom_parameter();
    float wobbleIntensity = fxParams.y;
    float gravityDotNormal = fxParams.z;  // Gravity modulation

    // Time-based animation (use world position as seed for variation)
    float time = params.uniforms().time();
    float positionSeed = worldPos.x * 3.14 + worldPos.y * 2.71 + worldPos.z * 1.41;

    // Sum of sines with different frequencies for natural motion
    // Wave 1: Primary slow wave (1 Hz)
    float wave1 = sin(time * 6.28 + positionSeed) * 0.5;

    // Wave 2: Secondary faster wave (2.5 Hz)
    float wave2 = sin(time * 15.7 + positionSeed * 1.3 + 1.2) * 0.3;

    // Wave 3: Tertiary detail wave (5 Hz)
    float wave3 = sin(time * 31.4 + positionSeed * 0.7 + 2.4) * 0.2;

    // Combine waves
    float wobbleX = (wave1 + wave2 + wave3);
    float wobbleY = (sin(time * 6.28 + positionSeed + 1.57) * 0.5 +  // 90° phase shift
                     sin(time * 15.7 + positionSeed * 1.3 + 2.77) * 0.3 +
                     sin(time * 31.4 + positionSeed * 0.7 + 3.97) * 0.2);

    // Modulate by gravity (stronger wobble when perpendicular to gravity)
    float gravityFactor = 1.0 - abs(gravityDotNormal);  // Max at perpendicular
    float wobbleScale = wobbleIntensity * gravityFactor * 0.02;  // 2cm max displacement

    // Distance from center modulation (less wobble at center)
    float distFromCenter = length(uv - float2(0.5));
    float centerFalloff = smoothstep(0.0, 0.5, distFromCenter);

    // Final displacement in tangent plane
    float2 displacement = float2(wobbleX, wobbleY) * wobbleScale * centerFalloff;

    // Apply offset (stay in XY plane for z=0 film)
    float3 offset = float3(displacement, 0.0);
    geo.set_model_position_offset(offset);
}

// Legacy texture-based wobble (fallback for dev/testing)
constexpr sampler wobbleSampler(coord::normalized,
                                address::clamp_to_edge,
                                filter::linear);

[[visible]]
void wobbleDisplacement_texture_geometry(realitykit::geometry_parameters params) {
    metal::texture2d<half> wobbleTex = params.textures().custom();
    float2 uv = params.geometry().uv0();
    half4 sample = wobbleTex.sample(wobbleSampler, uv);
    float2 displacement = float2(sample.rg);

    float displacementScale = 0.05f; // 5 cm max displacement
    float3 offset = float3(displacement, 0.0f) * displacementScale;

    params.geometry().set_model_position_offset(offset);
}
