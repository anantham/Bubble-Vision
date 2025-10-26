# Continuous Trails & Visual Enhancements - Complete Design

**Date:** 2025-10-24
**Status:** Design Complete, Ready for Implementation
**Architecture:** Approach J - "Stronger J" (Plane-Anchored Film + Volume Extrusion Cache)
**Conversation Reference:** See `conversation-2025-10-24.jsonl` for complete brainstorming session

---

## Executive Summary

This document specifies the complete architecture for Bubble Vision V1.1, transforming the MVP from single-tap bubble placement into a continuous trail painting system with production-grade visual effects.

**Core Vision:** "The iPad screen IS the soap film membrane."

**Key Deliverables:**
1. **Continuous trails** - Hold button + move iPad to paint volumetric soap-film trails through space
2. **Visual Tier 1+2 effects** - Edge highlighting, parallax patterns, refraction, sparkles, age-based ripples, front/back gradients, grazing fade
3. **IMU coupling** - Device motion drives film wobble, velocity advection, optional breath interaction
4. **Modular settings** - User-controlled visual effects, aperture shapes, performance tiers
5. **Performance guarantees** - 60 FPS on iPhone 12+, graceful degradation to iPhone XS (A12)

**Why "Stronger J":**
- Film plane locked to iPad screen (strongest "device is membrane" feel)
- Persistent volumetric trails via sparse tiled SDF cache
- Dual representation optimizes near (film plane) vs far (cached mesh) rendering
- Excellent RealityKit integration (occlusion, lighting, scene anchors)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Film Plane Implementation](#2-film-plane-implementation)
3. [Volume Extrusion Cache](#3-volume-extrusion-cache)
4. [IMU Coupling & Physics Dynamics](#4-imu-coupling--physics-dynamics)
5. [Seam Softening System](#5-seam-softening-system)
6. [Visual Effects Modules](#6-visual-effects-modules)
7. [Settings Architecture](#7-settings-architecture)
8. [Performance Budgets & Guardrails](#8-performance-budgets--guardrails)
9. [Instrumentation & Telemetry](#9-instrumentation--telemetry)
10. [Implementation Roadmap](#10-implementation-roadmap)
11. [Appendices](#11-appendices)

---

## 1. Architecture Overview

### 1.1 High-Level System Design

**"Stronger J"** is a dual-representation rendering system:

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER INTERACTION                          │
│  Press & Hold Button → Move iPad → Release                       │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FILM PLANE (Primary)                        │
│  • 2D mesh locked to iPad screen transform                       │
│  • Aperture-defined active region (circle/rect/full)             │
│  • All Tier 1+2 visual effects (refraction, sparkles, etc.)      │
│  • Pixels within ±5cm shade from this surface                    │
│  • Updated every frame (16.67ms @ 60 FPS)                        │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                  VOLUME EXTRUSION CACHE (Persistent)             │
│  • 8-12 world-locked SDF tiles (64³ voxels, R16F)               │
│  • Paint: Stamp negative SDF as iPad moves                       │
│  • Extract: Marching cubes every 6-10 frames → RealityKit mesh   │
│  • Pixels >5cm from screen shade from cached mesh                │
│  • Handles ARKit relocalization via tile origin rebasing          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SHADER BLENDING LAYER                         │
│  • Depth/angle-based cross-fade (film plane ↔ cache)            │
│  • Mini-SDF seam softening on near swept mesh (±2 neighbors)    │
│  • Smooth transitions, imperceptible handoffs                    │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Component Responsibilities

#### Film Plane
- **Geometry:** Simple quad or rounded-rect matching device aspect ratio
- **Transform:** `ARFrame.camera.transform` (z=0 in device space, NO forward offset)
- **Visual separation:** All depth cues (refraction, rim, gradient) in shader only
- **Aperture:** User-adjustable circle/rounded-rect/full-screen region
- **Purpose:** Primary interaction surface, "the iPad IS the film"

#### Volume Cache
- **Storage:** Sparse tiled SDF (8-12 tiles × 64³ voxels × R16F = 4-6 MB)
- **World-locked:** Tiles remain fixed in ARKit world frame
- **Paint process:** Stamp negative SDF brush matching aperture shape
- **Extraction:** Marching cubes generates RealityKit mesh chunks
- **Purpose:** Persistent trails that integrate with occlusion/lighting

#### Shader Blending
- **Near zone (±5cm):** Film plane with full Tier 1+2 effects
- **Mid/far zone (>5cm):** Cached mesh with standard iridescent material
- **Seam softening:** Mini-SDF evaluates ±2 neighbor slices for smooth normals
- **Purpose:** Unified visual continuity across representations

### 1.3 Data Flow

```
ARFrame (60 Hz)
  ├─> Camera transform → Film plane mesh transform
  ├─> Device motion → IMU coupling (wobble, velocity advection)
  └─> Current frame → Parallax-correct refraction sampling

User Input (Button)
  ├─> Press: Begin tracking path
  ├─> Hold + Move: Sample transforms when ΔPos >1.5cm or ΔRot >3°
  └─> Release: Finalize trail, trigger burst mesh extraction

Path Sampling (while painting)
  ├─> Detect movement threshold
  ├─> Compute segment P₀ → P₁
  ├─> Run paint kernel (compute shader)
  │    ├─> AABB test: which tiles affected?
  │    ├─> For each voxel: SDF to swept aperture shape
  │    └─> Update: sdf_new = smoothMin(sdf_old, dist - thickness, k=0.4)
  └─> Mark tiles dirty

Mesh Extraction (every 6-10 frames or on release)
  ├─> Run marching cubes on dirty tiles (GPU compute)
  ├─> Generate vertices/indices (cap: 120k tris/frame)
  ├─> Create/update RealityKit ModelEntity per tile
  └─> Clear dirty flags

Rendering (60 Hz)
  ├─> Film plane: CustomMaterial with all visual effects
  ├─> Cache mesh: Shared CustomMaterial (simpler, no refraction)
  ├─> Blend in fragment shader based on depth/angle
  └─> Seam softening on near swept mesh (local mini-SDF)
```

### 1.4 Why This Architecture

**Strengths:**
- ✅ Film plane at z=0 (device space) → strongest "screen is membrane" feel
- ✅ Parallax-correct refraction uses camera intrinsics → physically accurate
- ✅ Volume cache persistence → trails survive session backgrounding
- ✅ RealityKit integration → occlusion, lighting, scene anchors work correctly
- ✅ Modular visual effects → users can toggle for environment/accessibility
- ✅ Performance scalability → near/far quality split + auto-degradation

**Trade-offs:**
- ⚠️ Dual representation complexity → two systems to maintain
- ⚠️ Tile management overhead → origin shifting, epoch tracking
- ⚠️ Cache extraction latency → 6-10 frame delay acceptable

**Alternatives Considered (see `docs/research/rendering-options.md`):**
- **Approach A** (Pure GPU SDF Raymarch): Too GPU-intensive, poor occlusion
- **Approach B** (Mesh-Based Swept): No metaball blending, harder seams
- **Approach D** (Voxel SDF + Marching Cubes): Heavy memory, complex tile streaming
- **Approach I** (Mesh + Local Mini-SDF): Good fallback if cache proves too complex

---

## 2. Film Plane Implementation

### 2.1 Geometry & Transform

**Mesh specification:**
- **Topology:** Simple quad (2 triangles) or rounded-rect (16-32 verts for smooth corners)
- **Size:** Matches physical iPad screen dimensions in meters
  - Computed from device metrics: `widthMeters = nativePoints.width / PPI * 0.0254`
  - Example: iPad Pro 12.9" → ~0.25m × ~0.33m
- **Transform:** Updated every frame from `ARFrame.camera.transform`
  - **Critical:** Mesh at z=0 in device space (flush with screen glass)
  - **NO forward offset** (visual separation in shader only)

**Swift code:**
```swift
// ARCoordinator.swift
func updateFilmPlaneMesh(frame: ARFrame) {
    let cameraTransform = frame.camera.transform

    // Build transform: plane z=0 at camera origin
    // Right-handed: columns = (right, up, forward, position)
    var planeTransform = cameraTransform
    // Optional: tiny epsilon push for z-fighting (0.5mm)
    // planeTransform.columns.3 += simd_float4(0, 0, 0.0005, 0)

    filmPlaneEntity.transform.matrix = planeTransform

    // Update uniforms for shader
    filmParams.worldFromScreenPlane = planeTransform
    filmParams.filmSizeMeters = deviceMetrics.screenSizeMeters
}
```

### 2.2 Aperture System

**Purpose:** Define active region (cross-section shape for trail extrusion)

**Shapes supported:**
1. **Circle** - radius in meters (0.1 - 0.8m)
2. **Rounded-rect** - half-extents (ax, ay) + corner radius
3. **Full-screen** - matches device rounded-rect (auto-sized)

**Data structure:**
```metal
// Shader uniforms
struct FilmParams {
    float2 apertureCenterUV;     // 0..1 (usually 0.5, 0.5)
    float2 apertureRadiusUV;     // circle: (r,0), rect: (ax,ay)
    float  apertureCornerRadius; // meters
    uint   apertureType;         // 0=circle, 1=roundedRect, 2=fullScreen
    // ...
};
```

**Visual overlay (UI affordance):**
- Faint 1-2px rim drawn on-screen at aperture boundary
- Color-synced to film iridescence (hue matches current shader output)
- Shows user exactly which region will be extruded

**Swift code:**
```swift
// Settings → Uniforms
func updateAperture(settings: BubbleVisionSettings) {
    switch settings.apertureShape {
    case .circle:
        filmParams.apertureCenterUV = SIMD2(0.5, 0.5)
        filmParams.apertureRadiusUV = SIMD2(settings.apertureRadius, 0)
        filmParams.apertureType = 0

    case .roundedRect:
        filmParams.apertureCenterUV = SIMD2(0.5, 0.5)
        let halfExtentsUV = settings.apertureSize / deviceMetrics.screenSizeMeters
        filmParams.apertureRadiusUV = halfExtentsUV
        filmParams.apertureCornerRadius = settings.apertureCornerRadius
        filmParams.apertureType = 1

    case .fullScreen:
        filmParams.apertureCenterUV = SIMD2(0.5, 0.5)
        let halfExtentsUV = deviceMetrics.screenSizeMeters / 2.0
        filmParams.apertureRadiusUV = halfExtentsUV
        filmParams.apertureCornerRadius = deviceMetrics.screenCornerRadius
        filmParams.apertureType = 2
    }
}
```

### 2.3 Bezel-Locked Rim Lighting

**Goal:** Edge glow perfectly aligns with physical device bezels

**Implementation:**
```metal
// Fragment shader
float2 toEdge = abs(uv - apertureCenterUV) / apertureRadiusUV;
float edgeDist = 1.0 - max(toEdge.x, toEdge.y); // rounded-rect distance

// Fresnel-enhanced rim
float NdotV = saturate(dot(normalize(worldNormal), normalize(viewDir)));
float fresnel = pow(1.0 - NdotV, 2.5);

// Brighter at edges
float rimGlow = smoothstep(0.0, 0.05, edgeDist) * fresnel;
emissive += rainbowColor * rimGlow * 0.3;
```

**Corner anchors (optional):**
- Add tiny hemispherical bulges at 4 corners (2-3mm radius)
- Can be geometry (4 extra verts) or normal inflation in shader
- Provides stable 3D spatial reference tied to hardware

### 2.4 Parallax-Correct Refraction

**Critical:** Must use camera intrinsics for physically correct refraction

**Process:**
1. Get camera intrinsics (focal length fx, fy; principal point cx, cy)
2. Project ray from camera through pixel on physical screen plane
3. Offset ray by surface normal × refraction scale
4. Sample camera feed texture at offset UV

**Metal code:**
```metal
// Parallax-correct refraction
float3 n = normalize(worldNormal);
float NdotV = saturate(dot(n, normalize(viewDir)));

// Angle-dependent refraction (grazing angles bend more)
float fresnelFactor = pow(1.0 - NdotV, 5.0);
float k = refractionScale * (0.5 + 0.5 * pow(1.0 - NdotV, 2.0));

// Offset screen UV by normal projection
float2 refractUV = screenUV + n.xy * k;

// Sample camera feed (passed as texture)
float3 behindColor = cameraFeedTex.sample(sampler, refractUV).rgb;

// Mix with film color (subtle bend)
baseColor = mix(baseColor, behindColor, 0.15);
```

**Swift setup:**
```swift
// Pass camera feed to shader
func setupCameraFeed() {
    // ARKit provides camera feed as CVPixelBuffer
    let pixelBuffer = frame.capturedImage

    // Convert to Metal texture (use CVMetalTextureCache for efficiency)
    var textureOut: CVMetalTexture?
    CVMetalTextureCacheCreateTextureFromImage(
        nil, textureCache, pixelBuffer, nil,
        .bgra8Unorm, width, height, 0, &textureOut
    )

    if let metalTexture = CVMetalTextureGetTexture(textureOut) {
        filmMaterial.setParameter(.texture("cameraFeedTex", metalTexture))
    }
}
```

### 2.5 Front/Back Asymmetry

**Purpose:** User knows which side of film they're on

**Implementation:**
```metal
bool isFrontFace = dot(worldNormal, viewDir) < 0.0;

if (flags.frontBackGradient) {
    if (isFrontFace) {
        // Cool tint (cyan/white)
        baseColor = mix(baseColor, float3(0.9, 1.0, 1.0), 0.08);
    } else {
        // Warm tint (amber)
        baseColor = mix(baseColor, float3(1.0, 0.95, 0.85), 0.12);
    }
}
```

**Result:** Crossing through film shows subtle color shift (immediate spatial feedback)

---

## 3. Volume Extrusion Cache

### 3.1 Tile System Architecture

**Sparse tiled SDF:**
- **Tile count:** 8-12 (performance-dependent)
- **Tile dimensions:** 64³ voxels
- **Voxel format:** R16Float (signed distance in meters)
- **Voxel size:** 0.5-1.5 cm (tier-dependent: high=0.75cm, medium=1.0cm, low=1.5cm)
- **Memory:** ~512 KB per tile → 4-6 MB total for 8-12 tiles

**Tile frame (world-locked):**
```swift
struct TileFrame {
    var originWS: SIMD3<Float>        // world-space origin
    var axisWS: simd_float3x3         // columns = X, Y, Z (orthonormal)
    var voxelSize: Float              // meters per voxel
    var dim: Int32                    // 64
    var epoch: UInt32                 // incremented when tile repositioned
}
```

**Epoch system (prevents stale mesh flashing):**
- When tile moves/clears, increment `epoch`
- Mesh entities reference `(tileId, epoch)`
- Stale meshes (old epoch) are culled before rendering

### 3.2 Paint Process

**Trigger:** While button held, sample iPad transform when:
- ΔPosition > 1.5 cm, OR
- ΔRotation > 3°

**Per-segment stamp:**
```swift
struct SegmentStamp {
    var P0: SIMD3<Float>              // start position (world)
    var P1: SIMD3<Float>              // end position (world)
    var axisWS: simd_float3x3         // orientation for rounded-rect
    var halfExtents: SIMD2<Float>     // ax, ay (meters)
    var cornerRadius: Float           // meters
    var thickness: Float              // 3-5mm (visual sheet half-thickness)
    var smoothK: Float                // 0.35-0.45 (smooth-min blending)
}
```

**GPU compute kernel:**
```metal
kernel void paintSweptSegment(
    texture3d<half, access::read_write> sdfTex [[texture(0)]],
    constant TileFrameParams & tile     [[buffer(0)]],
    constant SegmentStampParams & seg   [[buffer(1)]],
    uint3 tid [[thread_position_in_grid]]
) {
    if (any(tid >= uint3(tile.dim))) return;

    // Index → world
    float3 pIdx = (float3(tid) + 0.5) * tile.voxelSize;
    float3 pWS = tile.originWS + tile.axisWS * pIdx;

    // Transform to segment local frame
    float3 toSeg = pWS - seg.P0;
    float3 segDir = normalize(seg.P1 - seg.P0);
    float segLen = length(seg.P1 - seg.P0);

    // Project onto segment
    float t = saturate(dot(toSeg, segDir) / segLen);
    float3 closestPt = seg.P0 + segDir * (t * segLen);

    // Distance to swept shape (circle or rounded-rect)
    float dist = sdSweptShape(pWS, closestPt, seg);
    dist -= seg.thickness;

    // Read current SDF
    half oldH = sdfTex.read(tid);
    float old = float(oldH);

    // Smooth-min blend
    float h = max(seg.smoothK - abs(old - dist), 0.0) / seg.smoothK;
    float smin = min(old, dist) - 0.25 * h * h * seg.smoothK;

    // Write back
    sdfTex.write(half(smin), tid);
}
```

**SDF shape helpers:**
```metal
// Circle (disc) swept along segment
float sdSweptCircle(float3 pWS, float3 closestPt, constant SegmentStampParams& seg) {
    float3 d = pWS - closestPt;
    // Project onto aperture plane
    float3 u = normalize(seg.axisWS.columns[0]);
    float3 v = normalize(seg.axisWS.columns[1]);
    float2 inPlane = float2(dot(d, u), dot(d, v));
    return length(inPlane) - seg.halfExtents.x; // radius stored in halfExtents.x
}

// Rounded-rect swept along segment
float sdSweptRoundedRect(float3 pWS, float3 closestPt, constant SegmentStampParams& seg) {
    float3 d = pWS - closestPt;
    float3 u = normalize(seg.axisWS.columns[0]);
    float3 v = normalize(seg.axisWS.columns[1]);
    float2 inPlane = float2(dot(d, u), dot(d, v));

    // 2D rounded-rect SDF
    float2 q = abs(inPlane) - (seg.halfExtents - seg.cornerRadius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - seg.cornerRadius;
}
```

### 3.3 Tile Management

**Ring buffer strategy:**
- Pre-allocate 8-12 tiles at startup
- As user moves, tiles "follow" camera (reposition far tiles ahead)
- When tile moves: clear SDF to +∞, increment epoch

**Origin shifting (ARKit relocalization):**
```swift
func handleRelocalization(deltaTransform: simd_float4x4) {
    // ARKit world origin shifted; update all tile origins
    for i in 0..<tiles.count {
        let oldOrigin = tiles[i].frame.originWS
        let oldOriginH = simd_float4(oldOrigin, 1.0)
        let newOriginH = deltaTransform * oldOriginH
        tiles[i].frame.originWS = simd_make_float3(newOriginH)
    }
    // SDF data remains valid (world-relative distances unchanged)
}
```

**1-voxel overlap halo:**
- When sampling at tile boundaries (marching cubes), read from neighbor tiles
- Prevents cracks where isosurface crosses boundaries
- Implementation: each tile stores references to 6 face neighbors

### 3.4 Marching Cubes Extraction

**Cadence:**
- Every 6-10 frames during painting (amortized cost)
- Immediate burst on button release (finalize trail)

**GPU compute kernel (simplified):**
```metal
kernel void marchingCubesTile(
    texture3d<half, access::sample> sdfTex [[texture(0)]],
    device Vertex* outVerts          [[buffer(0)]],
    device uint16_t* outIndices      [[buffer(1)]],
    constant TileFrameParams& tile   [[buffer(2)]],
    device atomic_uint* triCount     [[buffer(3)]],
    uint3 cid [[threadgroup_position_in_grid]]
) {
    // Standard marching cubes per cell
    // Sample 8 corners, lookup edge table, generate triangles
    // Use halo sampling for border cells (read from neighbor tiles)
    // Atomic increment triCount for output indexing
}
```

**Performance limits:**
- Cap: 120k triangles/frame (high tier), 80k (medium), 40k (low)
- If exceeded, defer remaining tiles to next frame
- Priority: tiles closest to camera first

**Output:**
- Vertices: position (float3), normal (float3), UV (float2) = 32 bytes/vert
- Indices: uint16 (64k verts max per tile, use multiple meshes if needed)
- Create RealityKit `ModelEntity` per tile with shared `CustomMaterial`

### 3.5 Blend Zones

**Near zone (±5cm from screen):**
- Shade from **film plane mesh** (full Tier 1+2 effects)
- Includes seam softening (mini-SDF to ±2 neighbors)

**Mid/far zone (>5cm from screen):**
- Shade from **cache mesh** (standard iridescent material)
- Simpler shader (no refraction, reduced sparkles)

**Transition (shader blending):**
```metal
// Compute distance from pixel to screen plane
float distToScreen = abs(dot(worldPos - screenPlaneOrigin, screenPlaneNormal));

// Blend factor (0=film, 1=cache)
float blendFactor = smoothstep(0.03, 0.07, distToScreen);

// Also consider viewing angle (grazing angles favor film plane)
float NdotV = abs(dot(worldNormal, viewDir));
blendFactor *= smoothstep(0.0, 0.2, NdotV);

// Fetch colors from both representations
float3 filmColor = /* film plane shader output */;
float3 cacheColor = /* cache mesh shader output */;

// Blend
float3 finalColor = mix(filmColor, cacheColor, blendFactor);
```

---

## 4. IMU Coupling & Physics Dynamics

### 4.1 Data Flow

```
ARFrame + CoreMotion (120 Hz)
  ├─> Gravity vector → Low-pass filter (α=0.15, ~150ms lag)
  ├─> Angular velocity → High-pass filter (β=0.25, flick sensitivity)
  └─> Camera transform delta → Screen tangent velocity (m/s)

Filtered outputs
  ├─> gravity2D (screen-down direction in UV space)
  ├─> omegaMag (angular velocity magnitude, rad/s)
  └─> velTangent2D (velocity along screen axes)

Shader uniforms (per-frame)
  ├─> FilmParams.gravity2D → wobble sag
  ├─> FilmParams.omegaMag → ripple triggers
  └─> FilmParams.velTangent → interference advection
```

### 4.2 Motion Coupling (Swift)

```swift
import CoreMotion

final class MotionCoupler {
    private let motion = CMMotionManager()

    // Filters
    private var gLPF = SIMD3<Float>(0, -1, 0)       // low-pass gravity
    private var prevOmega = SIMD3<Float>.zero
    private var omegaHP = SIMD3<Float>.zero         // high-pass angular vel

    // Tunables
    var gravityAlpha: Float = 0.15      // ~150 ms feel
    var omegaHPBeta: Float = 0.25       // flick sensitivity

    // Outputs
    var gravityDS = SIMD3<Float>(0, -1, 0)  // smoothed gravity (device-space)
    var omegaDS = SIMD3<Float>.zero         // angular velocity (device-space)
    var velTangent2D = SIMD2<Float>.zero    // screen tangent velocity (m/s)

    func start() {
        motion.deviceMotionUpdateInterval = 1.0 / 120.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    func update(from frame: ARFrame) {
        guard let dm = motion.deviceMotion else { return }

        // Gravity (low-pass)
        let g = SIMD3<Float>(Float(dm.gravity.x), Float(dm.gravity.y), Float(dm.gravity.z))
        gLPF = mix(gLPF, g, t: gravityAlpha)
        gravityDS = normalize(gLPF)

        // Angular velocity (high-pass for flicks)
        let om = SIMD3<Float>(Float(dm.rotationRate.x), Float(dm.rotationRate.y), Float(dm.rotationRate.z))
        let delta = om - prevOmega
        omegaHP = mix(omegaHP, delta, t: omegaHPBeta)
        omegaDS = om
        prevOmega = om

        // Screen tangent velocity
        let camT = frame.camera.transform
        let camPos = SIMD3<Float>(camT.columns.3.x, camT.columns.3.y, camT.columns.3.z)
        let dt: Float = 1.0 / 60.0
        let vWS = (camPos - prevCamPosWS) / max(dt, 1e-3)
        prevCamPosWS = camPos

        // Project onto screen plane
        let right = SIMD3<Float>(camT.columns.0.x, camT.columns.0.y, camT.columns.0.z)
        let up = SIMD3<Float>(camT.columns.1.x, camT.columns.1.y, camT.columns.1.z)
        velTangent2D = SIMD2<Float>(dot(vWS, right), dot(vWS, up))
    }

    private var prevCamPosWS = SIMD3<Float>.zero
}

// Helper: map gravity to screen UV axes
func motionToScreenGravity2D(_ gDS: SIMD3<Float>, cam: ARCamera) -> SIMD2<Float> {
    let T = cam.transform
    let right = SIMD3<Float>(T.columns.0.x, T.columns.0.y, T.columns.0.z)
    let up = SIMD3<Float>(T.columns.1.x, T.columns.1.y, T.columns.1.z)
    return SIMD2<Float>(dot(-gDS, right), dot(-gDS, up)) // "down" on screen
}
```

### 4.3 Wobble Field (Two Tiers)

**Tier A - Analytic wobble (fastest):**
```metal
float2 wobbleDisplacement(float2 uv, constant FilmParams& P, float t) {
    // Gravity sag (small constant offset)
    float2 gOff = normalize(P.gravity2D) * P.wobbleGain * 0.02;

    // Angular ripple (expanding ring from center)
    float2 d = uv - 0.5;
    float dist = length(d) + 1e-5;
    float phase = dist * 15.0 - t * (3.0 + 1.8 * saturate(P.omegaMag * 0.4));
    float ripple = sin(phase) * exp(-dist * 2.0) * (0.01 * saturate(P.omegaMag));

    return gOff + d * ripple;
}
```

**Tier B - 2D spring-damper heightfield (richer):**
```swift
struct WobbleGrid {
    let W = 32, H = 18
    var h = [Float](repeating: 0, count: 32*18)  // displacement
    var v = [Float](repeating: 0, count: 32*18)  // velocity

    // Parameters
    var k: Float = 120.0   // spring stiffness
    var c: Float = 0.65    // damping
    var lap: Float = 0.25  // laplacian coupling

    mutating func step(dt: Float, gravity2D: SIMD2<Float>, omegaMag: Float) {
        let drive = gravity2D.y * 0.015  // pull "down" vertically

        for y in 0..<H {
            for x in 0..<W {
                let i = y*W + x

                // Laplacian (4-neighbor)
                let hC = h[i]
                let hL = h[y*W + max(x-1, 0)]
                let hR = h[y*W + min(x+1, W-1)]
                let hU = h[max(y-1, 0)*W + x]
                let hD = h[min(y+1, H-1)*W + x]
                let lapTerm = lap * ((hL + hR + hU + hD) - 4.0*hC)

                // Spring-damper
                let a = -k*hC - c*v[i] + lapTerm

                // External drive
                let centerImpulse: Float = (omegaMag > 0.8) ? (0.05 * omegaMag) : 0.0
                let yBias = (Float(y) / Float(H-1) - 0.5) * drive

                v[i] += (a + yBias) * dt
                h[i] += v[i] * dt

                // Clamp
                h[i] = clamp(h[i], -0.08, 0.08)
            }
        }
    }
}

// Upload to Metal texture (R16F, 32×18)
func uploadWobbleGrid(_ grid: WobbleGrid, to texture: MTLTexture) {
    let region = MTLRegionMake2D(0, 0, grid.W, grid.H)
    let bytesPerRow = grid.W * 2  // R16F
    texture.replace(region: region, mipmapLevel: 0, withBytes: grid.h, bytesPerRow: bytesPerRow)
}

// Shader sampling
float h = wobbleTex.sample(sampler, uv).r;
float2 wobble = float2(0.0, h);  // vertical displacement
```

**Defaults:**
- Tier A: All devices (zero memory overhead)
- Tier B: High/medium tier (32×18 = 1.1 KB texture)
- Spring params: `k=120, c=0.65, lap=0.25, dt≈1/60`

### 4.4 Velocity-Advected Interference

**Purpose:** Color patterns flow with device movement

```metal
// Build screen-tangent advection vector
float2 vt = P.vel2D;  // m/s along right/up
float advMag = clamp(length(vt) * 0.3, 0.0, 1.2);
float3 adv = float3(vt.x, 0.0, vt.y) * (P.time * 0.5);

// Advect tri-planar noise coordinates
float3 uv3 = worldPos + adv;
float thickness = computeThickness(uv3, P.time);  // interference pattern
```

**Effect:** Rainbow bands slide in movement direction (reinforces film-device coupling)

### 4.5 Breath Interaction (Optional)

**Privacy-first design:**
- Default OFF, requires explicit user toggle
- Mic permission requested lazily on first enable
- Audio level processed on-device, **no storage or transmission**

**Implementation:**
```swift
import AVFoundation

final class BreathSensor {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private(set) var rmsSmoothed: Float = 0.0

    func start() throws {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine!.inputNode

        let format = inputNode!.outputFormat(forBus: 0)
        inputNode!.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Compute RMS
            let channelData = buffer.floatChannelData![0]
            let frameLength = UInt(buffer.frameLength)
            var sum: Float = 0.0
            for i in 0..<Int(frameLength) {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))

            // Smooth (fast attack, slow decay)
            self.rmsSmoothed = self.rmsSmoothed * 0.75 + rms * 0.25
        }

        try audioEngine!.start()
    }

    func stop() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
    }
}
```

**Shader effect:**
```metal
// Near bottom-center "mouth" hotspot
float2 q = (uv - float2(0.5, 0.85));  // tune per device
float fall = exp(-dot(q, q) * 60.0);
float breath = P.micRMS * fall;

// Thicken and increase shine
opacity = saturate(opacity + breath * 0.15);
roughness = max(0.05, roughness - breath * 0.10);
```

### 4.6 Haptics & Audio

**Haptic events:**
```swift
let hLight = UIImpactFeedbackGenerator(style: .light)
let hMedium = UIImpactFeedbackGenerator(style: .medium)
let hRigid = UIImpactFeedbackGenerator(style: .rigid)

func onSliceCommit() { hLight.impactOccurred() }         // trail segment added
func onButtonPress() { hMedium.impactOccurred() }        // button tap
func onBubblePop() { hRigid.impactOccurred(intensity: 0.7) }  // dissolve
```

**Audio (low-latency):**
- Preload buffers: `sheen.wav`, `pop.wav`, optional wind loop
- `AVAudioEngine` + `AVAudioPlayerNode` for <10ms latency
- Pitch/volume scaled by velocity and angular rate

---

## 5. Seam Softening System

### 5.1 Purpose

Eliminate visible hard seams between adjacent trail slices on the near swept mesh without global SDF cost.

**Problem:** Discrete sampling (rings every 1.5-2cm) creates normal discontinuities at junctions.

**Solution:** In fragment shader, evaluate tiny local SDF to ±2 neighbor slice rings, use smooth-min to bias normals/opacity.

### 5.2 Data Structure

**Per-Slice Ring (16-byte aligned, 96 bytes total):**
```metal
struct SliceRing {
    // Pose / shape
    float3 centerWS;      float thickness;       // 16 (meters)
    float3 normalWS;      uint  shapeType;       // 32 (0=circle, 1=roundedRect, 2=fullScreen)

    // Orthonormal in-plane basis (precomputed on CPU)
    float3 axisUWS;       float radius;          // 48 (circle radius; unused for rect)
    float3 axisVWS;       float2 halfExtents;    // 64 (rect half-extents ax, ay)
                          float cornerRadius;     // 68 (rect corner radius)
                          float _pad0;            // 72

    // Neighbor links
    uint n0, n1, n2, n3;   // 88 (indices; 0xFFFFFFFF = no neighbor)
    uint _pad1, _pad2;     // 96
};

constant uint NO_NBR = 0xffffffffu;
```

**Swift mirror:**
```swift
struct SliceRing {
    var centerWS: SIMD3<Float>
    var thickness: Float = 0.0035  // 3.5mm
    var normalWS: SIMD3<Float>
    var shapeType: UInt32          // 0=circle, 1=roundedRect, 2=fullScreen
    var axisUWS: SIMD3<Float>
    var radius: Float = 0.0
    var axisVWS: SIMD3<Float>
    var halfExtents: SIMD2<Float>
    var cornerRadius: Float = 0.0
    var _pad0: UInt32 = 0
    var n0, n1, n2, n3: UInt32     // neighbor IDs
    var _pad1, _pad2: UInt32
}
```

### 5.3 Neighbor Indexing

**When adding new slice:**
```swift
func addSlice(center: SIMD3<Float>, radius: Float, normal: SIMD3<Float>) {
    let newID = sliceRings.count

    // Build stable basis (reuse previous U to avoid twist)
    let (u, v) = makeSliceBasis(prevU: lastU, normal: normal)
    lastU = u

    var slice = SliceRing(
        centerWS: center,
        thickness: 0.0035,
        normalWS: normal,
        shapeType: 0,  // circle
        axisUWS: u,
        radius: radius,
        axisVWS: v,
        halfExtents: .zero,
        cornerRadius: 0,
        _pad0: 0,
        n0: NO_NBR, n1: NO_NBR, n2: NO_NBR, n3: NO_NBR,
        _pad1: 0, _pad2: 0
    )

    // Link to previous 2 slices
    if newID >= 1 {
        slice.n0 = UInt32(newID - 1)
        sliceRings[newID - 1].n2 = UInt32(newID)  // forward link
    }
    if newID >= 2 {
        slice.n1 = UInt32(newID - 2)
        sliceRings[newID - 2].n3 = UInt32(newID)
    }

    sliceRings.append(slice)
    dirtySliceBuffer = true
}

// Stable basis (prevents visual twisting)
func makeSliceBasis(prevU: SIMD3<Float>?, normal: SIMD3<Float>) -> (u: SIMD3<Float>, v: SIMD3<Float>) {
    let n = simd_normalize(normal)
    var u: SIMD3<Float>

    if let pu = prevU {
        // Project previous U onto new plane
        let proj = pu - simd_dot(pu, n) * n
        u = simd_length_squared(proj) > 1e-6 ? simd_normalize(proj) : simd_normalize(simd_cross(n, SIMD3(0,1,0)))
    } else {
        // First slice: pick any orthogonal axis
        let ref = abs(n.y) < 0.9 ? SIMD3<Float>(0,1,0) : SIMD3<Float>(1,0,0)
        u = simd_normalize(simd_cross(ref, n))
    }

    let v = simd_normalize(simd_cross(n, u))
    return (u, v)
}
```

### 5.4 SDF Primitives (Metal)

**2D shapes:**
```metal
// Rounded-rect (2D, centered)
inline float sdRoundedRect2D(float2 p, float2 a, float rc) {
    float2 q = abs(p) - (a - rc);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rc;
}

// Circle (2D, centered)
inline float sdDisc2D(float2 p, float r) {
    return length(p) - r;
}
```

**3D slice distance:**
```metal
// Project world point into slice local frame
inline float3 toSliceLocal(float3 pWS, device const SliceRing& R) {
    const float3 n = normalize(R.normalWS);
    const float3 u = normalize(R.axisUWS);
    const float3 v = normalize(R.axisVWS);
    float3 d = pWS - R.centerWS;
    return float3(dot(d, u), dot(d, v), dot(d, n)); // (u, v, w)
}

// Circle slice (finite-thickness disc)
inline float sdCircleSlice(float3 pWS, device const SliceRing& R) {
    float3 q = toSliceLocal(pWS, R);
    float d2 = sdDisc2D(q.xy, R.radius);
    return max(abs(q.z) - R.thickness, d2);
}

// Rounded-rect slice
inline float sdRoundedRectSlice(float3 pWS, device const SliceRing& R) {
    float3 q = toSliceLocal(pWS, R);
    float d2 = sdRoundedRect2D(q.xy, R.halfExtents, R.cornerRadius);
    return max(abs(q.z) - R.thickness, d2);
}

// Unified dispatcher
inline float sdSliceDistance(float3 pWS, device const SliceRing* rings, uint id) {
    const SliceRing R = rings[id];
    switch (R.shapeType) {
        case 0: return sdCircleSlice(pWS, R);
        case 1: return sdRoundedRectSlice(pWS, R);
        case 2: return sdRoundedRectSlice(pWS, R);  // full-screen → rounded-rect
        default: return sdCircleSlice(pWS, R);
    }
}
```

### 5.5 Smooth-Min Blending

```metal
inline float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - 0.25 * h * h * k;
}

inline float sdBlended(float3 p, device const SliceRing* rings, uint id, float k) {
    float d = sdSliceDistance(p, rings, id);
    const SliceRing R = rings[id];

    uint nbrs[4] = { R.n0, R.n1, R.n2, R.n3 };
    for (int i = 0; i < 4; i++) {
        uint nid = nbrs[i];
        if (nid == NO_NBR) continue;
        d = smin(d, sdSliceDistance(p, rings, nid), k);
    }
    return d;
}
```

### 5.6 Tetrahedral Gradient (Fast)

**3 taps vs 6 (central difference) → 40% cost reduction:**
```metal
inline float3 gradBlended(float3 p, device const SliceRing* rings, uint id, float k, float eps) {
    const float3 e1 = float3( 1,  1,  1);
    const float3 e2 = float3(-1, -1,  1);
    const float3 e3 = float3(-1,  1, -1);
    const float3 e4 = float3( 1, -1, -1);

    float d1 = sdBlended(p + eps*e1, rings, id, k);
    float d2 = sdBlended(p + eps*e2, rings, id, k);
    float d3 = sdBlended(p + eps*e3, rings, id, k);
    float d4 = sdBlended(p + eps*e4, rings, id, k);

    return normalize(float3(
        d1 - d2 - d3 + d4,
        d1 - d2 + d3 - d4,
        d1 + d2 - d3 - d4
    ));
}
```

### 5.7 Fragment Shader Integration

**Conditional gates (skip work when not near seams):**
```metal
void iridescent_seam_softened(realitykit::surface_parameters P) {
    auto surf = P.surface();
    auto geo = P.geometry();

    float3 wp = geo.world_position();
    float3 N = normalize(geo.world_normal());
    uint sid = geo.custom_attribute<uint>();  // sliceID

    device const SliceRing* rings = sliceBuffer;  // [[buffer(N)]]

    // Cheap gates: skip far from ring center or outside seam band
    const float d0 = sdSliceDistance(wp, rings, sid);
    float NdotV = abs(dot(N, -normalize(P.view().direction())));

    if (abs(d0) > 0.02 && NdotV < 0.6) {
        // Keep original normal; continue with shading
        surf.set_normal(half3(N));
        return;
    }

    // Blend with neighbors and adjust normal
    const float k = 0.35;
    const float eps = 0.005;  // 5mm

    float3 Nsdf = gradBlended(wp, rings, sid, k, eps);

    // Fade influence away from seam (strongest when |d0| small)
    float w = smoothstep(0.02, 0.0, abs(d0));
    float3 Nf = normalize(mix(N, Nsdf, 0.65 * w));  // cap at 65% influence

    surf.set_normal(half3(Nf));

    // Continue with iridescence/refraction using Nf...
}
```

**Tunables:**
- Smooth-min `k`: 0.35 (scale with slice spacing; tighter spacing → lower k)
- Gradient `eps`: 0.005 (5mm; increase to 0.002-0.003 for very small radii)
- Seam band: 0.02 m (2cm; only compute within this distance)
- Normal mix cap: 0.65 (prevents over-blending, keeps lighting stable)

**Performance:**
- Max 1 current + 4 neighbor SDF evaluations per fragment
- Tetrahedral gradient reuses same routine → ~4× fewer calls than naive
- Only active inside seam band (gated at fragment top)

---

## 6. Visual Effects Modules

### 6.1 Architecture

**Modular bitmask system** (no branch divergence):
```metal
// Single uint32 flags
// bit 0: edge highlighting
// bit 1: parallax patterns
// bit 2: front/back gradient
// bit 3: grazing fade
// bit 4: screen refraction
// bit 5: sparkle glints
// bit 6: age-based ripples

inline bool fxEnabled(uint mask, uint bit) {
    return ((mask >> bit) & 1u) != 0;
}
```

**Shader parameter block:**
```metal
struct FXParams {
    uint   flags;               // bitmask
    float  time;
    float2 screenUV;            // 0..1
    float3 worldPos;
    float3 viewDir;             // toward camera
    float3 worldNormal;
    float3 baseColor;
    float  opticalThickness;    // accumulator for interference
    float  opacity;

    // Refraction
    float2 screenUVParallax;    // parallax-correct UV
    float  refractionScale;     // 0.002-0.006

    // Age (for trails)
    float  age;                 // seconds
    float  maxAge;              // seconds
};
```

### 6.2 Tier 1 Effects (Depth Perception)

**Edge Highlighting (Fresnel Rim):**
```metal
inline void fxEdge(FXParams &P, thread float3 &emissive) {
    if (!fxEnabled(P.flags, 0)) return;

    float NdotV = saturate(dot(normalize(P.worldNormal), normalize(P.viewDir)));
    float f = pow(1.0 - NdotV, 2.5);

    P.opacity *= (0.7 + 0.3 * f);
    emissive += P.baseColor * (0.25 * f);
    P.opticalThickness += 80.0 * f;
}
```

**Parallax Patterns (Tri-Planar World-Space):**
```metal
inline void fxParallax(FXParams &P) {
    if (!fxEnabled(P.flags, 1)) return;

    float3 w = abs(P.worldNormal);
    w /= (w.x + w.y + w.z + 1e-5);
    float s = 8.0;  // cycles/m

    float2 uvX = P.worldPos.yz * s;
    float2 uvY = P.worldPos.xz * s;
    float2 uvZ = P.worldPos.xy * s;

    float2 vShift = normalize(P.viewDir.xy + 1e-5) * 0.25;
    uvX += vShift; uvY += vShift; uvZ += vShift;

    float nX = sin(uvX.x * 6.28318) * cos(uvX.y * 6.28318);
    float nY = sin(uvY.x * 6.28318) * cos(uvY.y * 6.28318);
    float nZ = sin(uvZ.x * 6.28318) * cos(uvZ.y * 6.28318);

    float pNoise = w.x*nX + w.y*nY + w.z*nZ;
    P.opticalThickness += pNoise * 60.0;
}
```

**Front/Back Gradient:**
```metal
inline void fxFrontBack(FXParams &P) {
    if (!fxEnabled(P.flags, 2)) return;

    bool front = dot(P.worldNormal, P.viewDir) < 0.0;
    float3 cool = float3(0.9, 1.0, 1.0);
    float3 warm = float3(1.0, 0.95, 0.85);
    P.baseColor = mix(P.baseColor, front ? cool : warm, front ? 0.08 : 0.12);
}
```

**Grazing Fade:**
```metal
inline void fxGrazingFade(FXParams &P) {
    if (!fxEnabled(P.flags, 3)) return;

    float NdotV = abs(dot(normalize(P.worldNormal), normalize(P.viewDir)));
    float fade = saturate((NdotV + 0.15) / 1.15);
    P.opacity *= fade;
}
```

### 6.3 Tier 2 Effects (Wet Glass Feel)

**Screen Refraction:**
```metal
inline void fxRefraction(FXParams &P, texture2d<float> cameraFeed, sampler s) {
    if (!fxEnabled(P.flags, 4)) return;

    float3 n = normalize(P.worldNormal);
    float NdotV = saturate(dot(n, normalize(P.viewDir)));
    float k = P.refractionScale * (0.5 + 0.5 * pow(1.0 - NdotV, 2.0));

    float2 rUV = P.screenUV + n.xy * k;
    float3 behind = cameraFeed.sample(s, rUV).rgb;
    P.baseColor = mix(P.baseColor, behind, 0.15);
}
```

**Sparkle Glints (Derivative-Driven):**
```metal
inline void fxSparkle(FXParams &P, thread float3 &emissive) {
    if (!fxEnabled(P.flags, 5)) return;

    float NdotV = saturate(dot(normalize(P.worldNormal), normalize(P.viewDir)));

    // Derivative magnitude (approx)
    float2 dNx = float2(dfdx(P.worldNormal.x), dfdy(P.worldNormal.x));
    float2 dNy = float2(dfdx(P.worldNormal.y), dfdy(P.worldNormal.y));
    float nVar = clamp(length(dNx) + length(dNy), 0.0, 1.0);
    float graze = saturate(1.0 - NdotV);
    float sFac = nVar * graze;

    // Hash (screen-space with jitter)
    float n = fract(sin(dot(P.screenUV * 1081.0 + P.time, float2(12.9898, 78.233))) * 43758.5453);
    float spark = step(0.995, n) * sFac;

    emissive += spark * 0.30 * P.baseColor;
}
```

**Age-Based Ripples:**
```metal
inline void fxAgeRipples(FXParams &P) {
    if (!fxEnabled(P.flags, 6)) return;
    if (P.maxAge <= 0.0f) return;

    float a = clamp(P.age / P.maxAge, 0.0, 1.0);
    float amp = mix(0.25, 0.8, a);
    float freq = mix(1.8, 0.9, a);

    float r = sin(P.worldPos.x * freq * 3.14159 + P.time) *
              cos(P.worldPos.y * freq * 3.14159 + P.time * 1.3);
    P.opticalThickness += r * amp * 80.0;
}
```

### 6.4 Call Sequence (Fragment Shader)

```metal
#include "VisualFX.metal"
#include "SeamSoftener.metal"

[[visible]]
void frag_main(realitykit::surface_parameters params) {
    auto surf = params.surface();
    auto geo = params.geometry();

    // Build FX parameter block
    FXParams fx;
    fx.flags = uniforms.fxMask;
    fx.time = uniforms.time;
    fx.screenUV = geo.uv0();
    fx.worldPos = geo.world_position();
    fx.viewDir = -geo.view_direction();
    fx.worldNormal = geo.world_normal();
    fx.baseColor = float3(1.0);
    fx.opticalThickness = 400.0;  // base thickness
    fx.opacity = 0.35;
    fx.refractionScale = uniforms.refractionScale;
    fx.age = /* from vertex attribute */;
    fx.maxAge = 60.0;  // 1 minute

    float3 emissive = float3(0);

    // Apply effects (modular, bitmask-gated)
    fxEdge(fx, emissive);
    fxParallax(fx);
    fxFrontBack(fx);
    fxGrazingFade(fx);
    fxRefraction(fx, cameraFeedTex, linearSampler);
    fxSparkle(fx, emissive);
    fxAgeRipples(fx);

    // Use fx.opticalThickness for iridescence
    float hue = fract(fx.opticalThickness * 0.0020 + uniforms.hueSeed);
    float3 rainbow = hsv2rgb(hue, 0.87, 1.0);
    float3 color = mix(rainbow, float3(1), 0.06);

    // Output
    surf.set_base_color(half3(color));
    surf.set_roughness(0.1 + 0.15 * pow(1.0 - NdotV, 2.5));
    surf.set_metallic(0.0);
    surf.set_opacity(fx.opacity);
    surf.set_emissive_color(half3(emissive));
}
```

### 6.5 Defaults (Ship With These)

- **Edge rim:** exp=2.5, emissive=0.25, thickness+80
- **Parallax:** scale=8.0 cycles/m, view shift=0.25
- **Refraction:** scale=0.0035, mix=0.15
- **Sparkle:** threshold=0.995, intensity=0.30
- **Age ripples:** amp 0.25→0.8, freq 1.8→0.9

---

## 7. Settings Architecture

### 7.1 Data Model

```swift
struct BubbleVisionSettings: Codable {
    var schemaVersion: Int = 1  // for future migrations

    // Visual Effects (Tier 1)
    var edgeHighlighting: Bool = true
    var parallaxPatterns: Bool = true
    var frontBackGradient: Bool = true
    var grazingFade: Bool = true

    // Visual Effects (Tier 2)
    var screenRefraction: Bool = true
    var sparkleGlints: Bool = true
    var ageBasedRipples: Bool = true

    // Physics Coupling
    var wobbleGain: Float = 1.0        // 0.0-2.0
    var breathInteraction: Bool = false // privacy default OFF

    // Aperture Configuration
    var apertureShape: ApertureShape = .circle
    var apertureRadius: Float = 0.4    // meters
    var apertureSize: SIMD2<Float> = SIMD2(0.6, 0.4)  // half-extents
    var apertureCornerRadius: Float = 0.05

    // Performance
    var performanceTier: PerformanceTier = .auto
    var maxBubbles: Int = 100

    // Color
    var color: ColorSettings = ColorSettings()

    // Debug
    var showDebugOverlay: Bool = false

    mutating func sanitize() {
        wobbleGain = wobbleGain.clamped(to: 0...2)
        apertureRadius = apertureRadius.clamped(to: 0.1...0.8)
        apertureCornerRadius = apertureCornerRadius.clamped(to: 0.0...0.2)
        maxBubbles = max(20, min(maxBubbles, 200))
    }
}

enum ApertureShape: String, Codable, CaseIterable {
    case circle, roundedRect, fullScreen
}

enum PerformanceTier: String, Codable, CaseIterable {
    case auto, high, medium, low
}

struct ColorSettings: Codable {
    var mode: ColorMode = .single
    var baseHSB: SIMD3<Float> = SIMD3(0.60, 0.85, 0.9)  // h, s, b
    var paletteHSB: [SIMD3<Float>] = []
    var cycleSpeed: Float = 0.6  // Hz
    var chromaJitter: Float = 0.0
}

enum ColorMode: String, Codable, CaseIterable {
    case single, paletteCycle, rainbow, ambientReactive
}
```

### 7.2 Persistence (Debounced)

```swift
@MainActor
final class SettingsManager: ObservableObject {
    @Published var settings: BubbleVisionSettings {
        didSet { scheduleSave() }
    }

    private let key = "BubbleVisionSettings"
    private var pendingWork: DispatchWorkItem?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           var decoded = try? JSONDecoder().decode(BubbleVisionSettings.self, from: data) {
            decoded.sanitize()
            self.settings = decoded
        } else {
            var defaults = BubbleVisionSettings()
            defaults.sanitize()
            self.settings = defaults
        }
    }

    private func scheduleSave() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [settings] in
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: self.key)
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func reset() {
        var defaults = BubbleVisionSettings()
        defaults.sanitize()
        settings = defaults
    }
}
```

### 7.3 Device Capability Detection

```swift
struct DeviceCapability {
    let hasLiDAR: Bool
    let hasSceneDepth: Bool
    let gpuFamily: MTLGPUFamily
    let processorGeneration: ProcessorGen
    let recommendedTier: PerformanceTier

    static var current: DeviceCapability {
        let device = MTLCreateSystemDefaultDevice()!

        // Depth detection (prefer sceneDepth over mesh reconstruction)
        let hasSceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let hasMeshReconstruction = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let hasLiDAR = hasSceneDepth || hasMeshReconstruction

        // GPU family
        var gpuFamily: MTLGPUFamily = .apple4
        if device.supportsFamily(.apple8) { gpuFamily = .apple8 }
        else if device.supportsFamily(.apple7) { gpuFamily = .apple7 }
        else if device.supportsFamily(.apple6) { gpuFamily = .apple6 }
        else if device.supportsFamily(.apple5) { gpuFamily = .apple5 }

        // Processor generation
        let procGen = detectProcessorGen()

        // Recommend tier
        let tier: PerformanceTier
        if procGen >= .a14 && hasLiDAR {
            tier = .high
        } else if procGen >= .a12 {
            tier = .medium
        } else {
            tier = .low
        }

        return DeviceCapability(
            hasLiDAR: hasLiDAR,
            hasSceneDepth: hasSceneDepth,
            gpuFamily: gpuFamily,
            processorGeneration: procGen,
            recommendedTier: tier
        )
    }
}

enum ProcessorGen: Int, Comparable {
    case a12 = 12, a13 = 13, a14 = 14, a15 = 15, a16 = 16
    static func < (lhs: ProcessorGen, rhs: ProcessorGen) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

### 7.4 Settings → GPU Uniforms

```swift
extension BubbleVisionSettings {
    var featureMask: UInt32 {
        var m: UInt32 = 0
        func set(_ bit: Int, _ on: Bool) { if on { m |= (1 << UInt32(bit)) } }
        set(0, edgeHighlighting)
        set(1, parallaxPatterns)
        set(2, frontBackGradient)
        set(3, grazingFade)
        set(4, screenRefraction)
        set(5, sparkleGlints)
        set(6, ageBasedRipples)
        return m
    }

    func toUniforms() -> BubbleVisionUniforms {
        BubbleVisionUniforms(
            featureMask: featureMask,
            wobbleGain: wobbleGain,
            apertureSize: apertureShape == .circle
                ? SIMD2(apertureRadius, 0)
                : apertureSize,
            cornerRadius: apertureCornerRadius,
            apertureShape: UInt32(ApertureShape.allCases.firstIndex(of: apertureShape) ?? 0),
            maxBubbles: UInt32(maxBubbles)
        )
    }
}
```

### 7.5 Style Presets

```swift
struct StylePreset: Identifiable {
    let id: String
    let name: String
    let apply: (inout BubbleVisionSettings) -> Void
}

let presets: [StylePreset] = [
    .init(id: "ethereal", name: "Ethereal") { s in
        s.edgeHighlighting = true
        s.frontBackGradient = true
        s.screenRefraction = false
        s.sparkleGlints = false
        s.wobbleGain = 0.6
    },
    .init(id: "glass", name: "Glass") { s in
        s.edgeHighlighting = true
        s.screenRefraction = true
        s.sparkleGlints = true
        s.parallaxPatterns = true
        s.wobbleGain = 1.0
    },
    .init(id: "ink", name: "Ink") { s in
        s.edgeHighlighting = true
        s.frontBackGradient = true
        s.screenRefraction = false
        s.sparkleGlints = false
        s.color.mode = .single
        s.color.baseHSB = SIMD3(0, 0, 0.2)  // desaturated
    },
    .init(id: "rainbow", name: "Rainbow") { s in
        s.color.mode = .rainbow
        s.parallaxPatterns = true
        s.sparkleGlints = true
        s.wobbleGain = 1.0
    }
]
```

---

## 8. Performance Budgets & Guardrails

### 8.1 Frame Time Budget (16.67ms @ 60 FPS)

```
Total: 16.67ms
├─ ARKit tracking: 2-4ms (system)
├─ Film plane: 2-3ms
│  ├─ Geometry: 0.3ms
│  ├─ Shader: 1.5-2.0ms
│  └─ Wobble sample: 0.2ms
├─ Cache mesh: 1-2ms
├─ SDF paint: 0.5-1.5ms (amortized)
├─ Marching cubes: 0.2-0.7ms (3 tiles/frame max)
├─ RealityKit: 3-5ms
└─ Reserve: 2-4ms
```

### 8.2 Tier Configurations

```swift
struct TierConfiguration {
    let wobbleGrid: SIMD2<Int>?
    let tileCount: Int
    let voxelSize: Float
    let maxBubbles: Int
    let mcTrianglesPerFrame: Int
    let enabledEffects: UInt32
    let refractionSamples: Int
    let sparkleDensity: Int

    static func forTier(_ tier: PerformanceTier) -> TierConfiguration {
        switch tier {
        case .high:
            return TierConfiguration(
                wobbleGrid: SIMD2(32, 18),
                tileCount: 12,
                voxelSize: 0.0075,
                maxBubbles: 150,
                mcTrianglesPerFrame: 120_000,
                enabledEffects: 0b1111111,  // all
                refractionSamples: 12,
                sparkleDensity: 3000
            )
        case .medium:
            return TierConfiguration(
                wobbleGrid: SIMD2(24, 14),
                tileCount: 8,
                voxelSize: 0.01,
                maxBubbles: 100,
                mcTrianglesPerFrame: 80_000,
                enabledEffects: 0b0111111,  // no age ripples
                refractionSamples: 8,
                sparkleDensity: 1500
            )
        case .low:
            return TierConfiguration(
                wobbleGrid: nil,  // Tier A only
                tileCount: 6,
                voxelSize: 0.015,
                maxBubbles: 60,
                mcTrianglesPerFrame: 40_000,
                enabledEffects: 0b0001111,  // no sparkles, no age
                refractionSamples: 4,
                sparkleDensity: 0
            )
        case .auto:
            return forTier(DeviceCapability.current.recommendedTier)
        }
    }
}
```

### 8.3 Memory Budgets

| Tier | SDF Cache | Mesh | Textures | Buffers | **Total** |
|------|-----------|------|----------|---------|-----------|
| High | ~6.3 MB   | ~1.2 MB | ~4.6 MB | ~0.5 MB | **~12.6 MB** |
| Medium | ~4.2 MB | ~0.8 MB | ~1.3 MB | ~0.5 MB | **~6.8 MB** |
| Low | ~3.1 MB   | ~0.4 MB | ~0.3 MB | ~0.5 MB | **~4.3 MB** |

### 8.4 Auto-Degradation Controller

```swift
final class PerformanceController {
    private let targetFPS: Double = 60.0
    private let emaAlpha: Double = 0.1
    private var frameTimeEMA: Double = 16.67
    private var cooldownFrames: Int = 0
    private var degradeCount: Int = 0

    func onFrame(gpuTime: Double, settings: inout BubbleVisionSettings) {
        frameTimeEMA = frameTimeEMA * (1 - emaAlpha) + gpuTime * emaAlpha

        guard cooldownFrames == 0 else {
            cooldownFrames -= 1
            return
        }

        let currentFPS = 1000.0 / frameTimeEMA

        if currentFPS < targetFPS * 0.80 {  // <48 FPS
            degrade(&settings)
            cooldownFrames = 60  // 1 second
            degradeCount += 1
        } else if currentFPS > targetFPS * 0.97 && degradeCount > 0 {
            upgrade(&settings)
            cooldownFrames = 180  // 3 seconds
        }
    }

    private func degrade(_ s: inout BubbleVisionSettings) {
        if s.sparkleGlints { s.sparkleGlints = false; return }
        if s.screenRefraction { s.screenRefraction = false; return }
        if s.ageBasedRipples { s.ageBasedRipples = false; return }
        if s.parallaxPatterns { s.parallaxPatterns = false; return }
        if s.maxBubbles > 40 { s.maxBubbles = max(40, s.maxBubbles - 20); return }
        if s.wobbleGain > 0.5 { s.wobbleGain -= 0.2; return }
    }

    private func upgrade(_ s: inout BubbleVisionSettings) {
        // Reverse order
        if s.wobbleGain < 1.0 { s.wobbleGain = min(1.0, s.wobbleGain + 0.2); return }
        // ... (reverse degrade sequence)
    }
}
```

### 8.5 Resource Guards

```swift
final class ResourceGuard {
    func enforceBubbleCap(bubbles: inout [BubbleAnchor], max: Int) {
        guard bubbles.count > max else { return }
        bubbles.sort { $0.createdAt < $1.createdAt }
        let toRemove = bubbles.count - max
        bubbles.removeFirst(toRemove)
    }

    func clampTileCount(requested: Int, budget: Int) -> Int {
        let tileSize = 64 * 64 * 64 * 2
        let maxTiles = budget / (tileSize * 2)
        return min(requested, maxTiles)
    }
}
```

---

## 9. Instrumentation & Telemetry

### 9.1 What NOT to Compress

**Critical data (preserve exactly):**
- Camera intrinsics/extrinsics per frame (fx, fy, cx, cy + pose)
- IMU raw + filtered outputs (both streams)
- Aperture state & FX bitmask per frame (not just current)
- RNG seeds for noise/sparkle/hue (bit-for-bit replay)
- Trail authoring deltas (P₀→P₁ stamps before resampling)
- Tile topology (origin shifts, epochs, halo on/off)
- Timing: CPU + GPU per workload

### 9.2 Black Box Capture

**Rolling ring buffer (15-30 seconds):**
- ARFrame pose/intrinsics (60 fps)
- DeviceMotion (native rate)
- Input events
- Settings + FX bitmask
- Trail stamps
- Performance counters

**On anomaly (FPS dip, crash, user report):**
- Freeze + write ring buffer (binary)
- Current tile SDFs (R16F, gzip only - NO quantization)
- Current meshes (16-bit indices OK)
- Screenshot + thumbnail
- Optional: short camera clip (privacy toggle, explicit consent)

### 9.3 Telemetry Targets

**Performance:**
- % frames with film shader >2.5ms
- Avg tiles dirty/frame
- Avg voxels touched/frame
- Avg triangles extracted/frame
- Degrade/upgrade events (what changed, FPS at time)

**Quality:**
- Relocalization count during painting
- Mean relocalization delta (transform difference)
- Seam softening invocations/frame
- Sparkle density actual vs target

**Crashes:**
- Last 3 GPU workloads (paint/MC/draw sizes)
- Memory usage at T-1s, T-100ms
- Tile epochs + positions

### 9.4 Compression Rules

- **Tiles:** gzip/deflate only, NO 8-bit quantization
- **Meshes:** OK to quantize positions 12-14 bit, store one unquantized chunk per K tiles
- **Streams:** delta-encode + zstd (lossless)
- **Audio:** RMS only (unless explicit consent for raw)

### 9.5 Watchdogs

**Frame spike detector:**
```swift
if gpuTime > 28.0 {  // ms
    spikeCount += 1
    if spikeCount >= 2 {  // twice in 2 seconds
        forceSafeMode(duration: 5.0)
        spikeCount = 0
    }
}
```

**Tile GC (garbage collection):**
```swift
// If tile off-camera & untouched >30 seconds
if tile.lastAccessTime + 30.0 < currentTime {
    exportTileToDisk(tile)  // persist SDF
    evictTileFromGPU(tile)  // keep bbox + epoch only
}
```

**MC budget (time-based):**
```swift
// Cap marching cubes by time, not just triangles
let mcStart = CACurrentMediaTime()
// ... extract triangles ...
let mcTime = CACurrentMediaTime() - mcStart
if mcTime > 0.002 {  // 2ms
    // Finish remaining tiles next frame
    break
}
```

### 9.6 Versioning

**Embed in every capture:**
```swift
struct CaptureMetadata: Codable {
    let appSemver: String           // e.g., "1.1.0"
    let shaderGitSHA: String        // or content hash
    let tileFormatVersion: Int      // bump when SDF layout changes
    let sliceStructStride: Int      // 96 bytes (SliceRing)
    let timestamp: Date
    let deviceModel: String
}
```

### 9.7 Golden Scene Test

**Nightly regression guard:**
```swift
func testGoldenScene() throws {
    let capture = loadCapture("golden-figure8-trail.capture")
    let rendered = renderCapture(capture, config: currentConfig)

    // Compare image SSIM
    let ssim = computeSSIM(rendered.keyFrames, capture.goldenFrames)
    XCTAssertGreaterThan(ssim, 0.95, "Visual regression detected")

    // Compare triangle counts
    let triDelta = abs(rendered.triangleCount - capture.goldenTriangleCount)
    XCTAssertLessThan(triDelta, 500, "Mesh extraction changed significantly")

    // Compare perf
    let perfDelta = rendered.avgFrameTime - capture.goldenFrameTime
    XCTAssertLessThan(perfDelta, 2.0, "Performance regression >2ms")
}
```

---

## 10. Implementation Roadmap

### 10.1 Phase 1: Foundation (Week 1)

**Goal:** Film plane + basic trail geometry (no cache yet)

- [ ] Film plane mesh at z=0 (device space)
- [ ] Aperture system (circle/rect/full)
- [ ] Bezel-locked rim lighting
- [ ] Parallax-correct refraction
- [ ] Basic trail: rapid-fire panes along path (Approach B)
- [ ] Tier 1 effects (edge, parallax, gradient, fade)

**Success criteria:**
- Film plane renders at 60 FPS
- Aperture overlay matches device bezels
- Refraction visually correct (no fisheye)
- Trail appears behind moving iPad

### 10.2 Phase 2: Volume Cache (Week 2)

**Goal:** Replace rapid-fire panes with SDF cache + marching cubes

- [ ] Tile allocation (8-12 tiles, 64³ R16F)
- [ ] Paint kernel (swept circle/rect SDF)
- [ ] Marching cubes extraction
- [ ] Tile management (ring buffer, epochs, origin shifting)
- [ ] Blend zones (film ↔ cache)

**Success criteria:**
- Trails persist in cache mesh
- ARKit relocalization works (tiles rebase cleanly)
- Marching cubes <2ms for 3 tiles/frame

### 10.3 Phase 3: Seam Softening (Week 3)

**Goal:** Smooth transitions between trail segments

- [ ] SliceRing buffer (96-byte aligned)
- [ ] Neighbor indexing (±2 slices)
- [ ] Stable basis computation (prevent twist)
- [ ] Mini-SDF evaluation (tetrahedral gradient)
- [ ] Fragment shader integration (gated by seam band)

**Success criteria:**
- No visible ridges at junctions
- Grazing-angle lighting smooth
- <0.2ms overhead in seam band

### 10.4 Phase 4: IMU & Visual FX (Week 4)

**Goal:** Device-coupled physics + all Tier 1+2 effects

- [ ] MotionCoupler (gravity LPF, omega HPF, vel tangent)
- [ ] Wobble Tier A (analytic)
- [ ] Wobble Tier B (32×18 grid, optional)
- [ ] Velocity advection
- [ ] Tier 2 effects (refraction, sparkles, age ripples)
- [ ] Haptics + audio

**Success criteria:**
- Tilt device → film sags with 150ms lag
- Flick device → ripples expand
- All 7 effects toggle independently

### 10.5 Phase 5: Settings & Performance (Week 5)

**Goal:** User controls + auto-degradation

- [ ] SettingsManager (debounced persistence)
- [ ] SwiftUI settings screen (Form layout)
- [ ] Style presets (4 presets: ethereal, glass, ink, rainbow)
- [ ] Device capability detection
- [ ] PerformanceController (EMA-based auto-degrade)
- [ ] ResourceGuard (bubble cap, tile clamp, OOM prevention)

**Success criteria:**
- Settings persist across launches
- Auto tier matches device (A12=low, A14+LiDAR=high)
- Auto-degrade triggers at <48 FPS, upgrades at >58 FPS

### 10.6 Phase 6: Polish & Ship (Week 6)

**Goal:** Instrumentation, testing, App Store submission

- [ ] Black box capture (ring buffer + anomaly triggers)
- [ ] Telemetry hooks (frame time breakdown, tile stats)
- [ ] Golden scene test (regression guard)
- [ ] QA matrix (3 devices × 4 scenarios)
- [ ] Privacy audit (mic permission, camera feed, no telemetry upload)
- [ ] App Store assets (screenshots, video, description)

**Success criteria:**
- All QA matrix green
- Capture playback reproduces original session
- App Store review approval

---

## 11. Appendices

### 11.1 File Structure

```
BubbleVision/
├─ AR/
│  ├─ ARCoordinator.swift         (session mgmt, existing)
│  ├─ MotionCoupler.swift         (NEW: IMU coupling)
│  ├─ TileManager.swift           (NEW: SDF cache)
│  ├─ TrailBuilder.swift          (NEW: slice rings, path sampling)
│  └─ PerformanceController.swift (NEW: auto-degradation)
│
├─ Shaders/
│  ├─ IridescentSurface.metal     (existing, upgrade)
│  ├─ SeamSoftener.metal          (NEW: include file)
│  ├─ VisualFX.metal              (NEW: include file)
│  └─ TilePaint.metal             (NEW: compute kernels)
│
├─ Materials/
│  └─ FilmMaterial.swift          (NEW: RealityKit wrapper)
│
├─ Models/
│  ├─ BubbleAnchor.swift          (existing)
│  ├─ SliceRing.swift             (NEW: seam data)
│  └─ TileFrame.swift             (NEW: SDF tile metadata)
│
├─ Settings/
│  ├─ SettingsManager.swift       (NEW)
│  ├─ SettingsView.swift          (NEW: SwiftUI)
│  └─ StylePresets.swift          (NEW)
│
└─ Utilities/
   ├─ DeviceCapability.swift      (NEW: tier detection)
   ├─ ResourceGuard.swift         (NEW: OOM prevention)
   └─ CaptureManager.swift        (NEW: telemetry)
```

### 11.2 Metal Buffer Layout

**Buffer indices (avoid conflicts):**
```metal
// Vertex stage
[[buffer(0)]] - per-vertex data (auto)
[[buffer(1)]] - per-instance data (auto)

// Fragment stage
[[buffer(2)]] - FilmParams uniforms
[[buffer(3)]] - SliceRing* buffer
[[buffer(4)]] - WobbleGrid texture (or [[texture(N)]])

// Compute stage
[[buffer(0)]] - TileFrame
[[buffer(1)]] - SegmentStamp
[[texture(0)]] - SDF 3D texture (read_write)
```

### 11.3 Shader Include Files

**See separate implementation files:**
- `SeamSoftener.metal` - Complete SDF system (Section 5)
- `VisualFX.metal` - Modular effects (Section 6)
- `FilmMaterial.swift` - RealityKit binding (Section 6)

### 11.4 Conversation Reference

**Full design discussion:** See `conversation-2025-10-24.jsonl` in project root.

Contains:
- All architectural alternatives (A-J) with trade-offs
- Performance optimization discussions
- Edge case handling
- GPT-5 instrumentation advice
- Complete code snippets and rationale

**Usage:** Future refinements or pivots should reference this conversation for context on why decisions were made.

---

## Document Status

**Validated:** All 8 sections + instrumentation reviewed with user
**Next Steps:** Create implementation files, set up worktree, begin Phase 1
**Maintainer:** Update this doc when architecture changes

**Revision History:**
- 2025-10-24: Initial comprehensive design (all sections)

---

**End of Design Document**
