// TilePaint.metal
// GPU compute kernels for painting SDF tiles and clearing them to +infinity.
// Reference: docs/plans/2025-10-24-continuous-trails-design.md Section 3

#include <metal_stdlib>
using namespace metal;

struct TileFrameParams {
    float3 originWS;
    float3x3 axisWS;
    float voxelSize;
    int dim;
    uint epoch;
    float2 _padding;
};

struct SegmentStampParams {
    float3 P0;
    float3 P1;
    float3x3 axisWS;
    float2 halfExtents;
    float cornerRadius;
    float thickness;
    float smoothK;
    uint shapeType;      // 0 = circle, 1 = rounded-rect
    uint3 _padding;
};

inline float sdRoundedRect2D(float2 p, float2 halfExtents, float r) {
    float2 q = abs(p) - (halfExtents - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

inline float sdSweptCircle(float3 pWS, float3 closestPt, constant SegmentStampParams& seg) {
    float3 d = pWS - closestPt;
    float3 u = normalize(seg.axisWS[0]);
    float3 v = normalize(seg.axisWS[1]);
    float2 inPlane = float2(dot(d, u), dot(d, v));
    float radius = seg.halfExtents.x;
    return length(inPlane) - radius;
}

inline float sdSweptRoundedRect(float3 pWS, float3 closestPt, constant SegmentStampParams& seg) {
    float3 d = pWS - closestPt;
    float3 u = normalize(seg.axisWS[0]);
    float3 v = normalize(seg.axisWS[1]);
    float2 inPlane = float2(dot(d, u), dot(d, v));
    return sdRoundedRect2D(inPlane, seg.halfExtents, seg.cornerRadius);
}

[[kernel]]
void paintSweptSegment(
    texture3d<half, access::read_write> sdfTex [[texture(0)]],
    constant TileFrameParams& tile              [[buffer(0)]],
    constant SegmentStampParams& seg            [[buffer(1)]],
    uint3 tid                                   [[thread_position_in_grid]]
) {
    if (any(tid >= uint3(tile.dim))) {
        return;
    }

    float segLen = length(seg.P1 - seg.P0);
    if (segLen < 1e-5) {
        return;
    }

    float3 segDir = (seg.P1 - seg.P0) / segLen;

    // Index → world-space position
    float3 pIdx = (float3(tid) + 0.5f) * tile.voxelSize;
    float3 pWS = tile.originWS + tile.axisWS * pIdx;

    float3 toSeg = pWS - seg.P0;
    float t = clamp(dot(toSeg, segDir) / segLen, 0.0f, 1.0f);
    float3 closestPt = seg.P0 + segDir * (t * segLen);

    float dist = 0.0f;
    if (seg.shapeType == 0u) {
        dist = sdSweptCircle(pWS, closestPt, seg);
    } else {
        dist = sdSweptRoundedRect(pWS, closestPt, seg);
    }

    dist -= seg.thickness;

    half currentValue = sdfTex.read(tid).x;
    float old = float(currentValue);

    float h = max(seg.smoothK - fabs(old - dist), 0.0f) / seg.smoothK;
    float blended = min(old, dist) - 0.25f * h * h * seg.smoothK;

    half4 writeValue = half4(half(blended), half(0.0f), half(0.0f), half(0.0f));
    sdfTex.write(writeValue, tid);
}

[[kernel]]
void clearTile(
    texture3d<half, access::write> sdfTex [[texture(0)]],
    constant TileFrameParams& tile        [[buffer(0)]],
    uint3 tid                             [[thread_position_in_grid]]
) {
    if (any(tid >= uint3(tile.dim))) {
        return;
    }
    half value = half(65504.0f);  // Largest finite half = +infinity sentinel
    sdfTex.write(half4(value, half(0.0f), half(0.0f), half(0.0f)), tid);
}
