//
//  IridescentSurface.metal
//  Bubble Vision
//
//  RealityKit CustomMaterial surface shader for thin-film iridescence
//

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

/// Custom parameters passed from RealityKit
struct CustomParams {
    float hueSeed;      // Phase shift for rainbow
};

/// HSV to RGB conversion
float3 hsv2rgb(float h, float s, float v) {
    float3 k = float3(1.0, 2.0/3.0, 1.0/3.0);
    float3 p = abs(fract(h + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

[[visible]]
void IridescentSurface(realitykit::surface_parameters params)
{
    // Extract built-in surface properties
    auto surface = params.surface();
    auto geo = params.geometry();

    float3 worldNormal = geo.normal();
    float3 viewDirection = -geo.view_direction();
    float2 uv = geo.uv0();

    // Derive hue seed from world position (deterministic per-bubble variation)
    // This avoids needing to pass custom parameters through the material API
    float3 worldPos = geo.model_position();  // Position in model space
    float hueSeed = fract(sin(dot(worldPos, float3(12.9898, 78.233, 45.164))) * 43758.5453);

    // Animate over time (2π cycle every ~6 seconds)
    float time = params.uniforms().time();

    // Fresnel-like factor (grazing angle enhances effect)
    float NdotV = saturate(dot(normalize(worldNormal), normalize(viewDirection)));
    float fresnel = pow(1.0 - NdotV, 2.5);

    // Simulate varying optical path difference (thickness variation)
    // Use low-frequency noise from UV and time for organic shimmer
    float thickness = 400.0
                    + 200.0 * sin(uv.x * 6.283 + time * 0.5)
                            * cos(uv.y * 6.283 + time * 0.7)
                    + 100.0 * sin((uv.x + uv.y) * 3.14 + time * 0.3);

    // Convert optical path to hue (interference color)
    // Scale factor determines how quickly colors cycle with angle/thickness
    float hue = fract((thickness * fresnel) * 0.002 + hueSeed);

    // Convert hue to RGB (saturated, bright)
    float3 rainbowColor = hsv2rgb(hue, 0.85, 1.0);

    // Mix with slight milky white base for soap-film look
    float3 baseColor = mix(rainbowColor, float3(1.0), 0.12);

    // Set RealityKit surface outputs
    surface.set_base_color(half3(baseColor));
    surface.set_roughness(0.1 + 0.15 * fresnel);
    surface.set_metallic(0.0);
    surface.set_opacity(0.35);  // Semi-transparent film

    // Subtle emissive glow at grazing angles
    surface.set_emissive_color(half3(rainbowColor * fresnel * 0.2));
}
