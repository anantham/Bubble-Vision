//
// WobbleDisplacement.metal
// Geometry modifier that offsets vertices using a displacement texture.
//

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

constexpr sampler wobbleSampler(coord::normalized,
                                address::clamp_to_edge,
                                filter::linear);

[[visible]]
void wobbleDisplacement_geometry(realitykit::geometry_parameters params) {
    auto customTex = params.textures().custom();
    float2 uv = params.geometry().uv0();
    float2 displacement = float2(customTex.sample(wobbleSampler, uv).rg);

    float displacementScale = 0.05f; // 5 cm max displacement
    float3 offset = float3(displacement.x, displacement.y, 0.0f) * displacementScale;

    params.geometry().set_model_position_offset(offset);
}
