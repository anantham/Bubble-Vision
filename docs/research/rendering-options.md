# Rendering Architecture Options for Continuous Trails

**Last Updated:** 2025-10-24
**Status:** Research Document
**Selected Approach:** J (Plane-Anchored Film + Volume Extrusion Cache) with enhancements

---

## Overview

This document catalogs all rendering architecture options considered for implementing continuous soap-film trails in Bubble Vision. Each approach has different trade-offs in visual quality, performance, implementation complexity, and integration with ARKit/RealityKit.

**Goal:** Enable users to hold button + move iPad to create volumetric trails where the iPad screen cross-section sweeps through 3D space, leaving persistent soap-film geometry.

---

## Quick Comparison Table

| Approach | Visual Quality | Performance | RealityKit Integration | Complexity | Timeline |
|----------|---------------|-------------|----------------------|-----------|----------|
| **A: Pure GPU SDF Raymarch** | Excellent | Low (GPU-heavy) | Difficult | High | 2-3 days |
| **B: Mesh-Based Swept Surface** | Good | Good | Excellent | Medium | 1-2 days |
| **C: Hybrid Instanced + SDF** | Very Good | Good | Good | Medium-High | 1.5-2 days |
| **D: Voxel SDF + Marching Cubes** | Excellent | Medium | Excellent | High | 2-3 days |
| **E: Screen-Space Volumetrics** | Very Good | Good | Difficult | Medium-High | 1-2 days |
| **F: Point-Splat Surfels** | Good | Excellent | Good | Low-Medium | 1 day |
| **G: Ribbon Stack (Multi-Plane)** | Fair | Excellent | Excellent | Low | 0.5 days |
| **H: Catmull-Rom Swept Surface** | Excellent | Good | Excellent | Medium | 1-2 days |
| **I: Mesh + Local Mini-SDF** | Very Good | Good | Excellent | Medium | 1-2 days |
| **J: Plane + Volume Cache** | Excellent | Good | Excellent | Medium-High | 1.5-2 days |

---

## Detailed Options

### A: Pure GPU SDF Raymarch

**Concept:** Store trail path as GPU buffer of transforms. Fragment shader raymarches through buffer to find closest point on swept path. Use smooth-min to blend adjacent segments (metaball effect).

**Architecture:**
```
Per-frame:
  - Update GPU buffer: [transform₀, transform₁, ..., transformₙ]
  - Fragment shader:
      for each pixel:
        raymarch through buffer
        evaluate SDF to swept capsule shape
        smooth-min blend adjacent segments
        apply visual effects (refraction, iridescence)
```

**Pros:**
- ✅ True organic metaball blending
- ✅ Infinitely smooth, no mesh seams
- ✅ All visual logic centralized in shader
- ✅ No CPU mesh generation overhead

**Cons:**
- ❌ Very GPU intensive (raymarch per pixel, per frame)
- ❌ ARKit mesh occlusion difficult (need depth buffer tricks)
- ❌ Hard to debug (no visible geometry in scene inspector)
- ❌ Complex shader code (~300+ lines of Metal)
- ❌ Performance scales poorly with trail length

**When to Choose:**
- You need true metaball blending at all costs
- Target high-end devices only (iPhone 13 Pro+)
- Visual quality trumps performance/debuggability

**Implementation Notes:**
- Use spatial acceleration (BVH or grid) to limit raymarch samples
- Early-out when ray exits trail bounds
- Consider temporal reprojection to amortize cost across frames

---

### B: Mesh-Based Swept Surface

**Concept:** Track iPad path in real-time. Generate triangle strip mesh connecting cross-section shapes along path. Each new path point adds a ring of vertices connected to previous ring.

**Architecture:**
```
Per-frame (while painting):
  - Sample iPad transform when moved >5cm or rotated >5°
  - Generate vertex ring matching aperture shape (circle/rect)
  - Connect to previous ring with triangle strip
  - Smooth vertex normals at junctions
  - Add mesh to RealityKit scene

Shader:
  - Standard CustomMaterial surface shader
  - Iridescence, refraction, sparkles, etc.
```

**Pros:**
- ✅ Integrates perfectly with RealityKit (ECS, occlusion, lighting)
- ✅ Easy debugging (visualize mesh in Xcode scene inspector)
- ✅ Modular (mesh builder separate from shader)
- ✅ Good performance (GPU rasterizes mesh efficiently)
- ✅ Well-understood technique

**Cons:**
- ❌ Not true metaball blending (approximation via vertex smoothing)
- ❌ CPU work for mesh generation (can be amortized)
- ❌ Potential seams between segments without smoothing
- ❌ Mesh complexity grows with trail length

**When to Choose:**
- You need solid RealityKit integration (occlusion, lighting)
- Debugging and iteration speed matter
- Acceptable to approximate metaball blending

**Implementation Notes:**
- Use ring topology: 32-48 vertices per slice for smooth circles
- Sample path adaptively (more samples on curves, fewer on straight)
- Smooth normals across 2-3 adjacent rings
- Pool mesh entities for reuse (avoid allocation thrash)

---

### C: Hybrid - Instanced Geometry + Shader SDF Blending

**Concept:** Spawn cylindrical segments rapidly along path as GPU instances. In fragment shader, evaluate SDF to nearby cylinders and smooth-min blend within radius. Spatial grid accelerates neighbor queries.

**Architecture:**
```
Per-frame (while painting):
  - Spawn cylinder instance every 2-5cm along path
  - Pass instance data: position, orientation, age, radius
  - Update spatial grid (hash map: cell → instance IDs)

Shader:
  - For each pixel, query spatial grid for nearby instances
  - Evaluate SDF to nearest 3-5 cylinders
  - Smooth-min blend
  - Apply visual effects
```

**Pros:**
- ✅ Incremental (start with cylinders, add blending later)
- ✅ Good performance (GPU instancing = 1 draw call)
- ✅ Some metaball smoothing (within blend radius)
- ✅ Easier debugging than pure SDF

**Cons:**
- ❌ Not true swept surface (approximated by dense sampling)
- ❌ Need spatial data structure (CPU or GPU)
- ❌ Shader complexity medium-high
- ❌ Blending limited to nearby cylinders (not global)

**When to Choose:**
- You want metaball-like smoothing without full SDF raymarch
- Incremental approach (ship cylinders first, refine later)
- Willing to manage spatial data structure

**Implementation Notes:**
- Use uniform grid (cell size = 2× max blend radius)
- Pass grid as texture or SSBO to shader
- Clamp blend evaluation to 3-5 nearest neighbors max

---

### D: Dynamic Voxel SDF (3D Texture) + On-GPU Marching Cubes

**Concept:** Maintain low/medium-res 3D SDF volume in world space. As you move, "paint" negative SDF into volume using screen-shape as brush. Periodically run marching cubes to emit mesh for RealityKit.

**Architecture:**
```
Initialization:
  - Allocate 8-12 world-locked tiles (64³ voxels each, R16F)
  - Initialize SDF to +∞

Per-frame (while painting):
  - Compute screen aperture sweep between last frame and current
  - Run compute kernel to stamp negative SDF into affected tiles
  - Mark tiles dirty
  - Optional: relaxation/dilate pass for organic softening

Every 6-10 frames:
  - Run marching cubes on dirty tiles (compute shader)
  - Generate/update RealityKit mesh chunks

Shader:
  - Standard surface shader on mesh (or SDF raymarch for preview)
```

**Pros:**
- ✅ True metaball blending (smooth-min in SDF space)
- ✅ Great occlusion (becomes mesh for RealityKit)
- ✅ Stable visuals (mesh persists between extractions)
- ✅ Easy to add wear/age (diffuse SDF over time)
- ✅ Editable trails (could erase regions later)

**Cons:**
- ❌ Memory + compute heavy (8 tiles × 64³ × 2 bytes ≈ 4-6 MB)
- ❌ Managing moving world origin & streaming tiles complex
- ❌ Quantization artifacts at low voxel resolution
- ❌ Marching cubes generates many triangles

**When to Choose:**
- You want real volumetric sculpting
- Persistent trails that can be edited/eroded
- Willing to invest in tile streaming and compute infrastructure

**Implementation Notes:**
- Use sparse tiles (only allocate near trail, not full grid)
- Implement origin shifting (rebase tiles when ARKit relocalizes)
- Tune voxel size: 0.5-1.0 cm balances quality/memory
- Use dual contouring instead of marching cubes for sharper features

---

### E: Screen-Space Volumetrics (Froxels) + One-Pass Raymarch

**Concept:** Build camera-aligned layered volume (froxels). Each frame, project swept geometry into froxel grid (opacity/color/thickness). Raymarch a few steps in fragment shader.

**Architecture:**
```
Per-frame:
  - Build froxel grid (e.g., 128×72×32 layers from near to far)
  - Rasterize trail geometry into grid (additive opacity/color)
  - Fragment shader raymarches through froxel grid (4-8 steps)
  - Composite with camera feed
```

**Pros:**
- ✅ Looks plush and volumetric
- ✅ Easy refraction and glow (sample behind in froxels)
- ✅ No heavy world-SDF (grid is camera-aligned, rebuilt each frame)
- ✅ Constant-time per pixel

**Cons:**
- ❌ View-dependent (trails look different from different angles)
- ❌ Tricky with AR occlusion (need to inject depth properly)
- ❌ Parallax can look "screen-spacey" (not stable in world)
- ❌ Froxel resolution limited (memory vs. quality trade-off)

**When to Choose:**
- You want lush, volumetric look for demos/videos
- Acceptable to have view-dependent artifacts
- Targeting cinematic visual quality over physical accuracy

**Implementation Notes:**
- Use exponential froxel depth slicing (more res near camera)
- Inject ARKit scene depth as occlusion layer
- Temporal reprojection to stabilize froxels across frames

---

### F: Point-Splat / Surfels (Instanced Quads or 3D Gaussians)

**Concept:** Emit dense "bubbles" as oriented surfels along swept path. Each splat carries radius/normal/thickness. Blend via weighted order-independent transparency (WBOIT) or additive.

**Architecture:**
```
Per-frame (while painting):
  - Emit 10-20 surfels per frame along path
  - Each surfel: position, normal, radius, age, hue seed
  - GPU instance quads or use 3D Gaussian splatting

Shader:
  - Billboard surfel toward camera (or use Gaussian)
  - Apply iridescence, sparkles per surfel
  - Blend via WBOIT or additive
```

**Pros:**
- ✅ Super incremental (start with billboards, refine later)
- ✅ Great for metaball-ish look with many overlapping splats
- ✅ Works well with GPU instancing (1 draw call)
- ✅ Fast to implement and debug

**Cons:**
- ❌ True watertight surfaces hard (gaps between splats)
- ❌ Can sparkle/shimmer at grazing angles (aliasing)
- ❌ Sorting/transparency load for WBOIT
- ❌ Doesn't integrate cleanly with occlusion (blended layer)

**When to Choose:**
- You want organic, blended trails quickly
- Acceptable to have "painterly" look rather than solid surface
- Rapid prototyping (can ship in 1 day)

**Implementation Notes:**
- Use WBOIT for order-independent blending (no sorting needed)
- Vary surfel radii with path curvature (tight turns = smaller splats)
- Add temporal noise to alpha to avoid banding

---

### G: Ribbon Stack / Multi-Plane "Fake Volume"

**Concept:** Instead of one plane, render 6-12 closely spaced parallel shells (tiny offsets along normal). Vary hue/opacity per layer. Animate offset with noise. Sweep these stacked ribbons along path.

**Architecture:**
```
Per-frame (while painting):
  - For each path slice, generate 6-12 parallel planes
  - Offset each by ±2-5mm along normal
  - Vary shader params per layer (hue shift, opacity scale)

Shader:
  - Same iridescent shader, different uniforms per layer
```

**Pros:**
- ✅ Very cheap (just more mesh instances)
- ✅ Surprisingly convincing depth (parallax between layers)
- ✅ Works with current shader immediately
- ✅ Easy to implement (extend mesh builder)

**Cons:**
- ❌ Not truly volumetric (still layered planes)
- ❌ Edge intersections reveal the trick
- ❌ More overdraw (6-12× geometry)

**When to Choose:**
- You need "it reads as volume now" quick win
- Acceptable to have layered-plane artifact at edges
- Want to iterate on visuals before investing in complex geometry

**Implementation Notes:**
- Use 6-8 layers (sweet spot for depth vs. overdraw)
- Animate layer offsets with slow noise for "breathing" effect
- Vary opacity: center layers opaque, outer layers transparent

---

### H: Catmull-Rom Swept Surface + CSG Union at Joints

**Concept:** Build high-quality swept tube/curtain by sampling a smoothed centerline (Catmull-Rom / B-spline). At joints/self-overlaps, add local CSG-like unions via additional joint caps/patches.

**Architecture:**
```
Per-frame (while painting):
  - Append transform to path buffer
  - Fit Catmull-Rom spline through recent N transforms
  - Sample spline uniformly, generate cross-section rings
  - At joint overlaps, detect and add blending caps

Shader:
  - Standard surface shader
```

**Pros:**
- ✅ Very RealityKit-friendly (clean mesh)
- ✅ Excellent continuity (smooth curves)
- ✅ Fewer verts for same smoothness (spline sampling)
- ✅ Predictable, debuggable

**Cons:**
- ❌ Not true metaball blending (just well-stitched mesh)
- ❌ Corner cases at extreme bends (self-intersection)
- ❌ CSG union detection adds complexity

**When to Choose:**
- You want "clean CAD-like sweep" with minimal shader magic
- Smooth curves important (drawing letters, shapes)
- Prefer CPU geometry work over GPU shader tricks

**Implementation Notes:**
- Use Catmull-Rom (C1 continuous) or cubic B-spline (C2 continuous)
- Sample adaptively: more points on high-curvature regions
- Detect self-overlap via bounding box tests, add blending patches

---

### I: Compute-Ribbon With Per-Slice Mini-SDF

**Concept:** Keep mesh-based swept surface (Approach B), but in fragment shader evaluate a *tiny* SDF only against current slice + 2-4 neighbors. Use smooth-min to soften seams locally.

**Architecture:**
```
Mesh generation:
  - Same as Approach B (triangle strip swept surface)

Per-instance data:
  - Slice ID, neighbor IDs, neighbor positions

Shader:
  - For each pixel, fetch positions of 2-4 neighbor slices (SSBO/texture)
  - Compute SDF to those local rings only
  - Smooth-min blend with current surface distance
  - Bias normals/opacity slightly to erase hard seams
```

**Pros:**
- ✅ Gets 80% of metaball look with 20% of cost
- ✅ Bounded shader work (only 2-4 neighbors, not whole trail)
- ✅ Same mesh pipeline as Approach B (easy upgrade)
- ✅ Local only (scales well with long trails)

**Cons:**
- ❌ Local only (won't fix distant overlap seams)
- ❌ Still need neighbor indexing (small SSBO)
- ❌ Not as smooth as global SDF

**When to Choose:**
- You like Approach B but want convincingly soft seams
- Acceptable to have local (not global) smoothing
- Want to upgrade existing mesh-based trail incrementally

**Implementation Notes:**
- Store ring positions in a texture or small SSBO (ring center + radius + normal)
- Limit to 2 neighbors (previous + next slice) for simplicity
- Use smooth-min k parameter ~0.2-0.4 for subtle blend

---

### J: Plane-Anchored Film + Volume Extrusion Cache ⭐ **SELECTED**

**Concept:** Maintain canonical film surface as 2D manifold locked to iPad screen. As you move, "bake" recent motion into deferred volume cache (tiled SDF). Shader blends fresh 2D film with baked volume along path.

**Architecture:**
```
Film Plane:
  - 2D mesh locked to iPad screen transform
  - Active region defined by aperture (circle/rect)
  - Full Tier 1+2 visual effects (refraction, sparkles, etc.)
  - Pixels near screen (±3-5cm) shade from this surface

Volume Cache:
  - 8-12 world-locked SDF tiles (64³ voxels each)
  - While painting: stamp negative SDF brush matching aperture
  - Every 6-10 frames: run marching cubes on dirty tiles
  - Pixels far from screen shade from cached mesh

Shader Blending:
  - Depth/angle-based blend between film plane and cached mesh
  - Mini-SDF seam softening on near swept mesh (neighbors ±2)
```

**Pros:**
- ✅ Best feel that "iPad IS the film" (screen is always primary surface)
- ✅ Perfect local control for Tier 1+2 visual effects
- ✅ Volume cache gives lasting trails without full global SDF
- ✅ Two representations optimize for different needs (near vs. far)
- ✅ Excellent RealityKit integration (cached mesh gets occlusion/lighting)

**Cons:**
- ❌ Two representations to sync (film plane ↔ cache)
- ❌ Cache management & origin shifting complexity
- ❌ More state to track (tiles, dirty flags, blend zones)

**When to Choose:**
- You want strongest UI affordance ("the screen is the membrane")
- Need persistent trails without full-scene SDF cost
- Willing to manage dual representation for quality/UX payoff

**Implementation Notes:**
- See `docs/plans/2025-10-24-continuous-trails-design.md` for full "Stronger J" architecture
- Film plane always renders at full quality (never skip for performance)
- Cache extraction can lag behind (6-10 frame delay acceptable)
- Origin shifting: rebase tile origins when ARKit relocalizes (not user-visible)

---

## Selection Matrix

### By Primary Goal

**Goal: Metaball blending at all costs**
→ **A** (Pure SDF Raymarch) or **D** (Voxel SDF + Marching Cubes)

**Goal: Fastest path to shipping**
→ **B** (Mesh-Based Swept), **F** (Surfels), or **G** (Multi-Plane)

**Goal: Best RealityKit integration**
→ **B** (Mesh-Based), **H** (Catmull-Rom), **I** (Mesh + Mini-SDF), or **J** (Plane + Cache)

**Goal: "iPad is the film" metaphor**
→ **J** (Plane-Anchored Film) ⭐

**Goal: Cinematic visuals for demo videos**
→ **E** (Froxels) or **A** (Pure SDF)

**Goal: Editable/sculpted trails**
→ **D** (Voxel SDF)

---

## Implementation Recommendation

**For Bubble Vision V1.1:** **Approach J** (Plane-Anchored Film + Volume Extrusion Cache)

**Rationale:**
1. Aligns perfectly with "iPad is the membrane" design philosophy
2. Supports all Tier 1+2 visual effects on film plane
3. Provides persistent trails via volume cache
4. Excellent RealityKit integration (occlusion, lighting, scene anchors)
5. Modular (can swap cache implementation later without changing film plane)

**Fallback:** If volume cache proves too complex, downgrade to **Approach I** (Mesh + Mini-SDF) as interim solution.

---

**Document Status:** Living research document. Update when new rendering techniques are discovered or approaches are prototyped.
