// EdgeRim.metal
// Thin additive rim shader for hiding residual seam cracks
// Reference: Phase 3 RealityKit-native seam band approach

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

/// Edge rim fragment shader - additive blending with premultiplied alpha
[[visible]]
void edgeRim_fragment(realitykit::surface_parameters params) {
    auto surface = params.surface();
    auto geo = params.geometry();

    // Read vertex alpha from COLOR attribute
    float vertexAlpha = 1.0;
    #if __METAL_VERSION__ >= 230
    if (geo.has_vertex_color()) {
        vertexAlpha = geo.vertex_color().a;
    }
    #endif

    // UV distance from edge (0 at edge, 1 at center)
    float2 uv = geo.uv0();
    float distFromCenter = length(uv - float2(0.5));
    float edgeDistance = smoothstep(0.35, 0.5, distFromCenter);

    // Fresnel for edge enhancement
    float3 N = geo.normal();
    float3 V = -geo.view_direction();
    float NdotV = saturate(dot(normalize(N), normalize(V)));
    float fresnel = pow(1.0 - NdotV, 3.0);

    // Rim intensity: strong at edges, modulated by Fresnel
    float rimIntensity = edgeDistance * fresnel * vertexAlpha;

    // Soft white/blue tint for rim
    float3 rimColor = mix(float3(1.0, 1.0, 1.0), float3(0.9, 0.95, 1.0), 0.3);

    // Premultiplied alpha for additive blending
    float3 premultipliedColor = rimColor * rimIntensity * 0.15;  // 15% max intensity

    // Output with additive blending
    surface.set_base_color(half3(premultipliedColor));
    surface.set_emissive_color(half3(premultipliedColor * 0.5));  // Slight glow
    surface.set_roughness(0.0);  // Very smooth for subtle effect
    surface.set_metallic(0.0);
    surface.set_opacity(half(rimIntensity * 0.2));  // Subtle transparency
}

/// Geometry modifier for slight depth bias (prevents z-fighting)
[[visible]]
void edgeRim_geometry(realitykit::geometry_parameters params) {
    auto geo = params.geometry();

    // Apply tiny offset along normal (0.5mm) to sit slightly above film plane
    float3 offset = geo.model_normal() * 0.0005;  // 0.5mm
    float3 newPosition = geo.model_position() + offset;

    geo.set_model_position_offset(newPosition - geo.model_position());
}
