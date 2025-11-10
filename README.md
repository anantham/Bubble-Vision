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

## Regression Checklist (Phases 1‑3)

Use this quick list when manually testing; see `TESTING.md` for full scripts.

| Area | Instrumentation | Manual Steps |
|------|-----------------|--------------|
| **Phase 1 – Film plane foundation** | `arView.debugOptions = [.showFeaturePoints, .showStatistics]` to watch mapping/FPS. | Launch → wait for “Ready to blow bubbles!” → place a pane → confirm button gating works and FPS ≥55. |
| **Phase 2 – Volume cache & persistence** | Xcode GPU frame capture (`Product ▸ Capture GPU Frame`) + Console logs from `TileManager` (“Allocated tile…”). | Paint 10 segments while walking → background app → relaunch in same room → ensure tiles reload and bubbles reappear. |
| **Phase 3 – Seam smoothing heuristics** | Inspect cache mesh normals in GPU capture, watch status text for seam toggle. | Paint a curved trail, walk toward/away: near film fades <0.5 m, cache mesh stays solid. Check `Settings ▸ Seam Softening` toggle. |

For timing/perf, use:
- Xcode **Debug Navigator → CPU/GPU** to note per-frame ms.
- `arView.debugOptions = .showStatistics` for FPS.
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
