# Bubble Vision V1.1 - Complete Documentation Index

**Date:** 2025-10-24
**Status:** Design Complete, Ready for Implementation
**Project:** Continuous Trails & Visual Enhancements

---

## Quick Navigation

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **[Main Design Doc](./2025-10-24-continuous-trails-design.md)** | Complete architecture (all 8 sections + instrumentation) | Start here. Comprehensive reference for entire V1.1 system |
| **[Rendering Options Research](../research/rendering-options.md)** | All alternatives (A-J) with trade-offs | Understanding why we picked "Stronger J" |
| **[Design Philosophy](../architecture/design-philosophy.md)** | Core principles, decision framework, anti-patterns | Evaluating new features or making pivots |
| **[SeamSoftener.metal](./implementation-SeamSoftener.metal)** | Drop-in Metal include for seam smoothing | Copy to project, include in CustomMaterial shader |
| **[VisualFX.metal](./implementation-VisualFX.metal)** | Drop-in Metal include for Tier 1+2 effects | Copy to project, include in CustomMaterial shader |
| **[FilmMaterial.swift](./implementation-FilmMaterial.swift)** | RealityKit binding wrapper | Copy to project, use as CustomMaterial wrapper |

---

## Document Structure

```
docs/
├─ plans/                          ← You are here
│  ├─ README.md                     (this file - navigation hub)
│  ├─ 2025-10-24-continuous-trails-design.md  (★ MAIN DESIGN DOC)
│  ├─ implementation-SeamSoftener.metal
│  ├─ implementation-VisualFX.metal
│  └─ implementation-FilmMaterial.swift
│
├─ research/
│  └─ rendering-options.md          (10 approaches A-J analyzed)
│
└─ architecture/
   └─ design-philosophy.md          (principles, pillars, decision framework)
```

---

## Implementation Phases (6 Weeks)

### ✅ Phase 0: Research & Design (Complete)
- [x] Brainstorm continuous trail approaches
- [x] Evaluate rendering architectures (A-J)
- [x] Design "Stronger J" system
- [x] Document all sections
- [x] Create implementation files

### 🔜 Phase 1: Foundation (Week 1)
**Goal:** Film plane + basic trail geometry

**Files to create:**
- `BubbleVision/AR/MotionCoupler.swift`
- `BubbleVision/Materials/FilmMaterial.swift`
- `BubbleVision/Shaders/FilmPlane.metal`

**Success criteria:**
- Film plane at z=0 (device space)
- Aperture overlay matches bezels
- Refraction visually correct
- Basic trail appears

**Reference:** Main Design Doc § 10.1

### 🔜 Phase 2: Volume Cache (Week 2)
**Goal:** SDF cache + marching cubes

**Files to create:**
- `BubbleVision/AR/TileManager.swift`
- `BubbleVision/Shaders/TilePaint.metal`
- `BubbleVision/Shaders/MarchingCubes.metal`

**Success criteria:**
- Trails persist in cache mesh
- Relocalization works
- Marching cubes <2ms

**Reference:** Main Design Doc § 10.2

### ✅ Phase 3: Seam Softening (Week 3)
**Goal:** Smooth junctions

**Deliverables:**
- [x] Slice orientation interpolation to reduce abrupt rotation changes
- [x] Shader-based edge fade with dynamic roughness boost
- [x] Seam softening toggle exposed in settings

**Reference:** Main Design Doc § 10.3

### 🔜 Phase 4: IMU & Visual FX (Week 4)
**Goal:** Device coupling + all effects

**Files to modify:**
- Copy `implementation-VisualFX.metal` → `BubbleVision/Shaders/`
- Update `FilmPlane.metal` to include VisualFX
- Create `BubbleVision/AR/WobbleGrid.swift` (Tier B)

**Success criteria:**
- Tilt → film sags
- Flick → ripples expand
- All 7 effects toggle

**Reference:** Main Design Doc § 10.4

### 🔜 Phase 5: Settings & Performance (Week 5)
**Goal:** User controls + auto-degradation

**Files to create:**
- `BubbleVision/Settings/SettingsManager.swift`
- `BubbleVision/Settings/SettingsView.swift`
- `BubbleVision/Settings/StylePresets.swift`
- `BubbleVision/Utilities/DeviceCapability.swift`
- `BubbleVision/Utilities/ResourceGuard.swift`
- `BubbleVision/AR/PerformanceController.swift`

**Success criteria:**
- Settings persist
- Auto tier matches device
- Auto-degrade at <48 FPS

**Reference:** Main Design Doc § 10.5

### 🔜 Phase 6: Polish & Ship (Week 6)
**Goal:** Instrumentation, testing, App Store

**Files to create:**
- `BubbleVision/Utilities/CaptureManager.swift`
- `BubbleVisionTests/GoldenSceneTests.swift`
- Update App Store assets

**Success criteria:**
- QA matrix green
- Capture playback works
- App Store approved

**Reference:** Main Design Doc § 10.6

---

## Key Concepts

### "Stronger J" Architecture

**Dual representation system:**
1. **Film Plane** - 2D mesh locked to iPad screen (z=0 device space)
   - All Tier 1+2 visual effects
   - Parallax-correct refraction
   - IMU-coupled wobble
   - Pixels within ±5cm

2. **Volume Cache** - Sparse tiled SDF (8-12 tiles × 64³ voxels)
   - Paint: Stamp negative SDF as iPad moves
   - Extract: Marching cubes → RealityKit mesh
   - Pixels >5cm from screen

3. **Shader Blending** - Depth/angle-based cross-fade
   - Mini-SDF seam softening on near mesh
   - Smooth transitions

**Why this works:**
- Film plane at device = strongest "screen is membrane" metaphor
- Volume cache = persistent trails with occlusion/lighting
- Dual representation = near quality, far performance

### Visual Effects (Tier 1+2)

**Tier 1 (Depth Perception):**
- Edge highlighting (Fresnel rim)
- Parallax patterns (tri-planar world-space)
- Front/back gradient (side differentiation)
- Grazing fade (prevent pops)

**Tier 2 (Wet Glass Feel):**
- Screen refraction (bend background)
- Sparkle glints (micro-facet twinkle)
- Age-based ripples (temporal layering)

**Implementation:** Bitmask-controlled, no branch divergence, modular toggles

### Performance Tiers

| Tier | Device | Wobble | Tiles | Voxel Size | Max Bubbles | Effects |
|------|--------|--------|-------|------------|-------------|---------|
| High | A14+ LiDAR | 32×18 grid | 12 | 0.75cm | 150 | All 7 |
| Medium | A12-A13 | 24×14 grid | 8 | 1.0cm | 100 | No age ripples |
| Low | A12 min | Analytic | 6 | 1.5cm | 60 | No sparkles/age |

**Auto-degradation:** EMA-based controller drops effects at <48 FPS, restores at >58 FPS

---

## Critical Design Decisions

### 1. Film Plane at z=0 (Device Space)

**Decision:** Render film mesh exactly on screen plane (z=0), NOT offset forward

**Rationale:**
- Strongest "screen is membrane" feel
- Visual separation (refraction, rim) in shader only
- Avoids parallax/occlusion fighting

**Alternative rejected:** 1-2cm forward offset (causes depth conflicts)

### 2. Parallax-Correct Refraction

**Decision:** Use camera intrinsics (fx, fy, cx, cy) for ray projection

**Rationale:**
- Physically correct bending (not arbitrary quad offset)
- Locks bend to real screen position
- Validates against captured camera feed

**Alternative rejected:** Simple UV offset by normal (looks "fake")

### 3. Sparse Tiled SDF (Not Full-Scene)

**Decision:** 8-12 tiles × 64³ voxels, ring buffer management

**Rationale:**
- Bounded memory (4-6 MB vs. unbounded)
- Predictable performance (cap at 3 tiles/frame MC)
- Handles relocalization cleanly (tile rebasing)

**Alternative rejected:** Full-scene voxel grid (OOM risk, streaming complexity)

### 4. Tetrahedral Gradient (Not Central Diff)

**Decision:** 3-tap tetrahedral stencil for SDF normals

**Rationale:**
- 40% cost reduction (3 vs 6 samples)
- Good numerical stability
- Bounded neighbor queries

**Alternative rejected:** 6-tap central differences (slower, no quality gain)

### 5. Bitmask Flags (Not Struct of Bools)

**Decision:** Single `uint32` with bit-per-effect

**Rationale:**
- No GPU branch divergence
- Single memcpy to shader
- Fast toggle in settings

**Alternative rejected:** Struct of bools (padding, slower, branching)

---

## Instrumentation & Telemetry

### What NOT to Compress

**Preserve exactly (bit-for-bit):**
- Camera intrinsics/extrinsics per frame
- IMU raw + filtered outputs
- Aperture state & FX bitmask per frame
- RNG seeds (sparkle, hue jitter)
- Trail authoring deltas (P₀→P₁)
- Tile topology (epochs, origins, halo)
- Timing: CPU + GPU per workload

**Why:** Enables bit-for-bit replay of captured sessions for debugging

### Black Box Capture

**Rolling ring buffer (15-30s):**
- ARFrame pose/intrinsics (60 fps)
- DeviceMotion (native rate)
- Input events
- Settings + FX bitmask
- Trail stamps
- Performance counters

**On anomaly:**
- Freeze + write ring buffer (binary)
- Tile SDFs (R16F, gzip only - NO quantization)
- Meshes (16-bit indices OK)
- Screenshot + thumbnail
- Optional camera clip (privacy toggle)

**Reference:** Main Design Doc § 9

---

## Common Pitfalls & Solutions

### Pitfall 1: Compressing SDF Data

**Problem:** Quantizing R16F→R8 to save memory corrupts distance gradients

**Solution:** gzip/deflate only, never quantize. 2× compression is enough.

**Why:** Marching cubes needs accurate gradients for normal calculation

---

### Pitfall 2: Forgetting Tile Epochs

**Problem:** Tile repositions without epoch increment → stale meshes flash

**Solution:** Increment epoch when clearing/moving tile, cull meshes with old epoch

**Why:** Mesh entities cache `(tileId, epoch)`; epoch mismatch = invisible

---

### Pitfall 3: No Seam Band Gating

**Problem:** Running seam softening on every fragment kills performance

**Solution:** Early-out if `abs(d0) > 0.02 && NdotV < 0.6`

**Why:** Only fragments near junctions (<2cm) need blending

---

### Pitfall 4: Single-Tap Wobble Grid Update

**Problem:** Updating 32×18 grid in one frame causes spike

**Solution:** Update in background (GCD), upload texture async

**Why:** Spring-damper sim is CPU-bound; amortize across frames

---

### Pitfall 5: No Camera Feed Conversion Cache

**Problem:** Converting ARFrame→MTLTexture every frame allocates

**Solution:** Use `CVMetalTextureCache` for zero-copy conversion

**Why:** Texture cache reuses buffers, no per-frame allocation

---

## FAQ

### Q: Why "Stronger J" instead of pure SDF raymarch?

**A:** Pure SDF (Approach A) is too GPU-intensive and breaks RealityKit occlusion. J gives us metaball smoothing (via cache) while keeping film plane in RealityKit's pipeline.

---

### Q: Can we skip the volume cache and just use rapid-fire panes?

**A:** Yes, that's the fallback (Approach I). Ship Phase 1-4 with rapid panes, add cache in Phase 2 if needed. Cache enables true metaball blending + persistence.

---

### Q: Why 96 bytes for SliceRing (so large)?

**A:** 16-byte alignment requirements + stable basis (axisU, axisV) + shape params (circle vs rect). Could compress to 64 bytes with quaternion+flags, but clarity > 32 bytes.

---

### Q: What if user enables all 7 effects on iPhone XS?

**A:** `PerformanceController` auto-degrades at <48 FPS. First to drop: sparkles, refraction, age ripples. User sees "⚡︎" glyph indicating Auto intervention.

---

### Q: How do we handle ARKit relocalization mid-painting?

**A:** Tile origins are world-space. On relocalization event, apply `deltaTransform` to all tile origins. SDF data stays valid (distances are relative).

---

## Next Steps

1. **Review main design doc** (2025-10-24-continuous-trails-design.md)
2. **Set up worktree** (isolate V1.1 work from main branch)
3. **Begin Phase 1** (film plane foundation)
4. **Iterate with code review** after each phase

**Estimated timeline:** 6 weeks to shippable V1.1

---

## Contact & Feedback

**Project lead:** Aditya
**Design session:** 2025-10-24 (see conversation JSONL for full context)
**Status:** Ready for implementation

---

**Document maintained by:** Claude Code
**Last updated:** 2025-10-24
