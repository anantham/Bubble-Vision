# Bubble Vision - Design Philosophy

**Last Updated:** 2025-10-24
**Status:** Living Document

---

## Core Vision

**"The iPad screen IS the soap film."**

Bubble Vision transforms the physical iPad into a magical membrane that sweeps volumetric soap-film trails through augmented reality space. The device itself becomes the interaction medium, not just a window into AR.

---

## Design Pillars

### 1. Physical Believability

**Principle:** The film must read as a real, physical soap membrane anchored to the iPad's glass.

**Implementation:**
- Bezel-locked rim lighting that matches device rounded-rect
- Parallax-correct refraction using camera intrinsics
- IMU-coupled wobble (device tilt → film sag/ripple)
- Velocity-advected interference patterns (colors flow with movement)

**Why it matters:** Users intuitively understand physical objects. When the digital film follows the laws of physics and responds to device motion, it becomes tangible rather than abstract.

---

### 2. Zero Latency Perception

**Principle:** The interaction must feel immediate and butter-smooth, even if actual latency exists.

**Implementation:**
- 120-180ms temporal hysteresis on wobble/glints (anticipatory feel)
- Haptic + audio feedback synced to slice commits
- Film plane always renders at full quality (cache can lag)

**Why it matters:** AR breaks presence the moment interaction feels laggy. By designing for *perceived* rather than *actual* zero latency, we maintain the magic.

---

### 3. Modular Visual Richness

**Principle:** Users should be able to tune visual effects to their environment, colorblindness, or aesthetic preference.

**Implementation:**
- Settings checklist for each visual effect (edge highlighting, refraction, sparkles, etc.)
- Each effect is a shader module that can be toggled independently
- Performance budget maintained regardless of combination

**Why it matters:** Different environments (bright sun, dim room, glassy office) and user needs (accessibility) require different visual strategies. A one-size-fits-all shader will fail in edge cases.

---

### 4. Graceful Degradation

**Principle:** The experience should work excellently on cutting-edge hardware but still function on 5-year-old devices.

**Implementation:**
- Multi-tier rendering: near-field gets full quality, far-field uses cheaper billboards
- LOD system for mesh complexity based on distance and device capability
- Auto-disable expensive effects (SDF raymarch, metaball blending) on older GPUs

**Why it matters:** AR apps are already demanding on hardware. By designing for graceful degradation from day one, we maximize reach while still leveraging new capabilities.

---

### 5. The "iPad is the Membrane" Metaphor

**Principle:** All interaction models should reinforce that the screen surface is the film, not a controller for remote objects.

**Implementation:**
- Film plane is always locked to screen transform
- Aperture overlay shows active region on-screen
- Bezel-locked corners provide stable 3D spatial anchors
- Volume extrusion happens "behind" the screen as you move

**Why it matters:** This metaphor is the app's unique value proposition. Breaking it (e.g., placing bubbles "out there" instead of "here at the screen") destroys the core experience.

---

## Technical Philosophy

### Prefer RealityKit Native Solutions

**Why:** RealityKit provides AR-first rendering, ECS architecture, CustomMaterial support, and future visionOS compatibility. While we use custom Metal shaders, we stay within RealityKit's framework rather than dropping to SceneKit or raw Metal rendering.

**Trade-offs:** Some advanced techniques (full-screen SDF raymarch) are harder in RealityKit, but the integration benefits (occlusion, lighting, scene anchors) outweigh the constraints.

---

### Separate Visual Innovation from Core Stability

**Why:** The AR session management, persistence, and tracking are **hard to get right** and must be rock-solid. Visual effects are **safe to experiment with** because they don't affect state or stability.

**Implementation:**
- `ARCoordinator.swift` handles session/tracking/persistence (stable, tested)
- Shader files (`IridescentSurface.metal`, future `FilmPlane.metal`) contain visual effects (rapid iteration)
- Clear separation allows visual designers to work independently from AR engineers

---

### Evidence-Based Performance Budgets

**Why:** AR rendering at 60 FPS is non-negotiable for presence. We set budgets based on device capabilities, not guesses.

**Current Budgets:**
- **60 FPS target** on iPhone 12+ (main development target)
- **45+ FPS** acceptable on iPhone XS (minimum supported)
- **Max 100 bubbles** with FIFO pruning
- **≤250MB memory** for all AR state + meshes

**Process:** Profile on oldest supported device first, optimize there, enjoy headroom on newer hardware.

---

### Design for Debuggability

**Why:** AR bugs are notoriously hard to reproduce (environmental, tracking-dependent, device-specific).

**Implementation:**
- Status text shows tracking state, world mapping status, bubble count
- Mesh-based rendering (visible in Xcode scene inspector) over pure shader techniques
- Session state persists to JSON (human-readable, diffable)
- Extensive logging with `print()` statements for state transitions

**Trade-off:** Debug UI/logging adds code, but the ability to actually fix bugs is worth it.

---

## Evolution Strategy

### V1.0 (MVP - Shipped)
- Single-tap bubble placement
- ARWorldMap persistence
- Basic iridescent shader
- LiDAR occlusion (graceful fallback)

**Philosophy:** Ship the simplest version that demonstrates the core value ("place magic bubbles in AR that persist").

---

### V1.1 (Current Focus)
- **Visual Tier 1+2:** Edge highlighting, parallax, refraction, sparkles, age-based ripples
- **Continuous trails:** "Stronger J" architecture (film plane + volume cache)
- **Settings:** Modular toggles for visual effects

**Philosophy:** Elevate the visual quality to "wow" and introduce the continuous trail mechanic that makes the "iPad is membrane" metaphor real.

---

### V2.0 (Future)
- Multi-user sessions (MultipeerConnectivity)
- Cloud persistence (iCloud + CloudKit)
- People occlusion & interaction
- Advanced physics (surface tension, tear/pop dynamics)

**Philosophy:** Build social/persistent features that extend the magic beyond a single session.

---

## Decision Framework

When evaluating new features or technical approaches, ask:

1. **Does it reinforce "iPad is the membrane"?**
   ✅ Yes → Strong fit
   ⚠️ Neutral → Consider carefully
   ❌ No → Probably wrong feature

2. **Can we implement it modularly?**
   ✅ Yes → Low risk to try
   ❌ No → High cost, must be confident

3. **Does it work on iPhone XS (A12)?**
   ✅ Yes → Ship it
   ⚠️ Degraded mode possible → Ship with fallback
   ❌ No → Reconsider or gate to Pro models only

4. **Does it improve visual believability OR interaction fluidity?**
   ✅ Yes → Aligns with pillars
   ❌ No → Probably feature creep

---

## Anti-Patterns to Avoid

### ❌ Remote Object Placement
Placing objects "out there" in the scene (like most AR apps) breaks the membrane metaphor. The film must always originate from the screen.

### ❌ Opaque Surfaces
Soap films are inherently semi-transparent with refraction. Making them opaque destroys the physical believability.

### ❌ Static Visuals
Real soap films shimmer, wobble, and respond to air currents. Static textures feel dead.

### ❌ Hidden Interaction Affordances
Users must always see the active aperture region and understand what tapping/holding will do. Invisible touch targets break AR presence.

### ❌ Single-Path Visual Strategy
Different environments and user needs require different depth cues. A shader that works in bright sun may fail in dim rooms.

---

## Open Questions & Evolution Points

### Question: Should we support stylus/Apple Pencil for precision trails?
- **Pro:** Fine control, artist use cases
- **Con:** Breaks "blow bubbles" metaphor, adds input complexity
- **Decision:** Defer to V2.0, gather user feedback first

### Question: Should trails be editable after creation?
- **Pro:** Undo mistakes, sculpting mode
- **Con:** Complex state management, unclear interaction model
- **Decision:** V1.1 trails are immutable; explore editing in V2.0 with research spike

### Question: How do we handle very long sessions (>1000 bubbles)?
- **Current:** 100-bubble cap with FIFO
- **Better:** Spatial partitioning + distance-based culling
- **Decision:** Gather telemetry in V1.1 on actual session lengths before optimizing

---

## Success Metrics

### User Experience
- **"Wow" moment:** ≤30 seconds from app open to first bubble placed
- **Session length:** Target avg 5+ minutes (users explore, not just demo once)
- **Persistence validation:** 50%+ users return after first session and bubbles restore

### Technical
- **Frame rate:** 95%+ frames at 60 FPS on iPhone 12+
- **Relocalization:** <5 seconds to restore session in same room
- **Crash rate:** <0.1%

### Business (if applicable)
- App Store rating: ≥4.5⭐
- Viral coefficient: >0.5 (if social features added)

---

**This document evolves with the project. Update it when architectural decisions are made or philosophy shifts.**
