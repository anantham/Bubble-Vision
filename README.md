# Bubble Vision

**A shimmering AR soap-bubble window creator for iOS**

---

## What It Does

Bubble Vision lets you "blow" iridescent soap-film panes into real space using your iPhone's camera. Panes persist across sessions via ARWorldMap relocalization, creating a magical layer of semi-transparent rainbow windows anchored to the physical world.

---

## Key Features (MVP)

- ✅ **RealityKit + ARKit** world tracking
- ✅ **CustomMaterial Metal shader** for thin-film iridescence
- ✅ **ARWorldMap persistence** (local, same-device)
- ✅ **LiDAR occlusion** on Pro models (graceful fallback)
- ✅ **ARCoachingOverlayView** for user onboarding
- ✅ **Session gating** (button disabled until mapped & normal tracking)
- ✅ **Auto-save** on background/termination

---

## Requirements

- **iOS 16.0+**
- **ARKit-capable device** (A12+ recommended)
- **Xcode 15+**

**Optional (for best experience):**
- LiDAR scanner (iPhone 12 Pro and later, iPad Pro)

---

## Project Structure

```
BubbleVision/
├── BubbleVisionApp.swift          # App entry point
├── Info.plist                      # Camera permissions + ARKit requirement
├── Models/
│   └── BubbleAnchor.swift          # Codable data model for bubbles
├── AR/
│   ├── ARCoordinator.swift         # Session management, persistence, gating
│   └── ARViewContainer.swift       # UIViewRepresentable wrapper + coaching
├── Views/
│   └── ContentView.swift           # Main UI (AR + blow button)
├── Shaders/
│   └── IridescentSurface.metal     # CustomMaterial thin-film shader
└── Assets.xcassets/
```

---

## How to Build & Run

1. **Open the project:**
   ```bash
   cd "Bubble Vision"
   open BubbleVision.xcodeproj
   ```

2. **Set your Development Team** in Xcode:
   - Select the **BubbleVision** target
   - Go to **Signing & Capabilities**
   - Set **Team** to your Apple Developer account

3. **Connect a physical device** (AR doesn't work in Simulator)

4. **Build and Run** (⌘R)

---

## Usage

1. **Launch the app** → ARCoachingOverlayView guides you to scan environment
2. **Wait for status** to show "Ready to blow bubbles!"
3. **Tap the wind button** to place a shimmering pane ~0.8m forward
4. **Move around** to see iridescence shift with viewing angle
5. **Tap "Save Session"** or background the app → state persists
6. **Relaunch** → after relocalization, bubbles reappear in same spots

---

## Architecture Decisions

| Choice                     | Rationale                                                                 |
|----------------------------|---------------------------------------------------------------------------|
| **RealityKit**             | AR-first, PBR, ECS, CustomMaterial support. SceneKit is soft-deprecated. |
| **ARWorldMap**             | Local same-device persistence; cloud/multi-user deferred to V2.           |
| **CustomMaterial shader**  | Thin-film iridescence requires custom Metal; RealityKit allows it.        |
| **Session gating**         | Button disabled until `trackingState == .normal && worldMappingStatus ∈ {.mapped, .extending}` prevents poor UX. |
| **100-bubble cap**         | Perf safety; oldest bubbles fade when exceeded.                           |
| **LiDAR feature-flag**     | Mesh occlusion on Pro models; graceful fallback on A12+ devices.          |

---

## Performance Budgets

- **Target FPS:** 60
- **Max bubbles:** 100 (auto-prune oldest)
- **Mesh complexity:** ~200 verts per pane (rounded rect)
- **Texture res:** N/A (procedural shader)
- **Draw calls:** 1 per bubble (CustomMaterial batching)

---

## Known Limitations (MVP)

- **No trails/ribbons** (coming in V2)
- **No multi-user** (requires ARCollaborationData + networking)
- **No geo-anchoring** (ARGeoAnchor for outdoor city-scale deferred)
- **Persistence is device-local** (no iCloud sync)
- **Shader fallback** is simple transparent material (rare on iOS 16+)

---

## Stretch Roadmap (Post-MVP)

- [ ] **Hold-to-paint trails** (ribbon mesh generation)
- [ ] **Surface-locked mode** (raycast/mesh projection)
- [ ] **Color/size picker** (press-hold gesture)
- [ ] **People occlusion** (automatic on iOS 15+)
- [ ] **Multi-user sessions** (MultipeerConnectivity)
- [ ] **Cloud persistence** (iCloud + ARWorldMap sharing)

---

## Code Entry Points

| File                         | Purpose                                                                 |
|------------------------------|-------------------------------------------------------------------------|
| `ARCoordinator.swift:43`     | `run()` / `loadStateAndRun()` — session startup logic                   |
| `ARCoordinator.swift:104`    | `placeBubble()` — pane creation & transform calculation                 |
| `ARCoordinator.swift:182`    | `session(_:didUpdate:)` — tracking & mapping state gating               |
| `IridescentSurface.metal:31` | Thin-film shader (hue, thickness, Fresnel)                              |
| `ContentView.swift:42`       | Blow button UI + disabled state                                         |

---

## Testing Matrix

| Environment          | Motion               | Device          | Expected Result                        |
|----------------------|----------------------|-----------------|----------------------------------------|
| Bright sun           | Slow pan             | iPhone 11       | Bubbles visible, no occlusion          |
| Dim room             | Fast whip            | iPhone 14 Pro   | Coaching overlay, then stable tracking |
| Glassy office        | Walk away/return     | iPad Pro (2022) | Relocalization within 3s               |
| Cluttered room       | Rapid placement (10) | iPhone 13       | All bubbles persist                    |

---

## Phase 3: RealityKit-Native Seam Bands

**Approach:** Geometry-driven seam softening within RealityKit constraints

### Components

1. **Vertex Alpha Seam Bands** (`FilmPlaneBuilder.swift:98-187`)
   - Extrudes 1–2 vertex strips along slice edges (inner ring at 70% radius, outer at 100%)
   - Quadratic falloff alphas: `alpha = (1-t)²` where t=1 at outer edge
   - Packed into COLOR attribute, read in shader via `geo.vertex_color().a`

2. **CPU Topology Cache** (`SeamTopologyCache.swift`)
   - Tracks adjacent-slice pairs within 5cm threshold
   - Marks "dirty" seams when distance changes >5mm
   - Throttled refinement at 30 Hz (max 32 seams/update)

3. **Edge Rim Pass** (`EdgeRim.metal`, `FilmPlaneBuilder.swift:75-251`)
   - Separate ModelEntity with thin additive rim shader
   - 0.5mm depth bias prevents z-fighting
   - Premultiplied alpha for subtle crack hiding

4. **Analytic Wobble** (`WobbleDisplacement.metal:14-59`)
   - Sum of 3 sine waves (1 Hz, 2.5 Hz, 5 Hz) - no texture uploads
   - Modulated by gravity via `custom_parameter.z`
   - 2cm max displacement, center falloff

5. **FX Packing** (`FilmMaterial.swift:9-15`)
   ```
   custom_parameter (SIMD4<Float>):
   .x = bitmask (bit 7: seam, bits 0-6: FX)
   .y = wobble intensity (0.0-2.0)
   .z = gravity · normal (-1.0 to 1.0)
   .w = device tier (0=A, 1=B, 2=C)
   ```

6. **Instrumentation** (`SeamInstrumentation.swift`)
   - EMA-smoothed metrics (α=0.1): FPS, mesh update duration, refinement rate
   - Safety thresholds: FPS ≥55, mesh updates <1.5ms
   - Debug modes: seam-only, topology overlay, dirty seams, alpha heatmap

### Acceptance Criteria

| Metric | Threshold | Instrumentation |
|--------|-----------|----------------|
| **No visible cracks** | Zero gaps >1 pixel at 1m distance | Visual inspection + edge rim pass |
| **Mesh update cost** | <1.5 ms per MeshResource.replace() | `SeamInstrumentation.meshUpdateDuration` |
| **Refinement rate** | ≤30 Hz (throttled) | `SeamInstrumentation.refinementRate` |
| **FPS maintenance** | ≥55 FPS with 20 slices | `arView.debugOptions = .showStatistics` |
| **Dirty seam backlog** | <10% of total seams | `SeamInstrumentation.dirtySeams / totalSeams` |

### Failure Cookbook

| Symptom | Likely Cause | Remediation |
|---------|--------------|-------------|
| Visible halo around edges | Vertex alpha falloff too steep | Increase seam band width 2cm→3cm in `FilmPlaneBuilder.swift:101` |
| Flicker during movement | Mesh updates not throttled | Verify 30 Hz cap in `SeamTopologyCache.swift:27` |
| Cracks at sharp angles | Rim pass insufficient | Increase rim width or depth bias in `EdgeRim.metal:56` |
| FPS <55 | Too many refinements/frame | Reduce `maxSeamsPerUpdate` from 32→16 in `SeamTopologyCache.swift:30` |

---

## Regression Checklist (Phases 1‑3)

Use this quick list when manually testing; see `TESTING.md` for full scripts.

| Area | Instrumentation | Manual Steps |
|------|-----------------|--------------|
| **Phase 1 – Film plane foundation** | `arView.debugOptions = [.showFeaturePoints, .showStatistics]` to watch mapping/FPS. | Launch → wait for “Ready to blow bubbles!” → place a pane → confirm button gating works and FPS ≥55. |
| **Phase 2 – Volume cache & persistence** | Xcode GPU frame capture (`Product ▸ Capture GPU Frame`) + Console logs from `TileManager` (“Allocated tile…”). | Paint 10 segments while walking → background app → relaunch in same room → ensure tiles reload and bubbles reappear. |
| **Phase 3 – RK-native seam bands** | Enable `SeamInstrumentationHUD`, watch dirty seam counter + mesh update duration. | Paint curved trail → verify no cracks at 1m → check FPS ≥55 → toggle debug modes (seam-only, alpha heatmap) → confirm <1.5ms mesh updates. |

For timing/perf, use:
- Xcode **Debug Navigator → CPU/GPU** to note per-frame ms.
- `arView.debugOptions = .showStatistics` for FPS.
- `SeamInstrumentation` HUD for live seam metrics.
- Memory graph for tile allocation (<250 MB at 8 tiles).

Record results in `TESTING.md`’s Regression Tests section.

---

## Privacy & Permissions

- **Camera access required:** declared in `Info.plist` `NSCameraUsageDescription`
- **No telemetry** in MVP (optional analytics: session start/stop, relocalization latency)
- **No images stored** (ARWorldMap contains feature points only, not raw video)

---

## License

MIT (modify as needed)

---

## Credits

- **Thin-film shader** inspired by physical optics interference equations
- **ARKit best practices** from Apple's official documentation
- **Gemini strategic roadmap** adapted into build-ready implementation

---

**Built with ARKit + RealityKit + Metal on iOS 16+**
