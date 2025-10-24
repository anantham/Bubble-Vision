# Bubble Vision - Architecture Documentation

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                           │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              ContentView (SwiftUI)                         │ │
│  │  • Status display                                          │ │
│  │  • Blow button (gated on isReady)                         │ │
│  │  • Save button                                             │ │
│  │  • Scene phase lifecycle handling                          │ │
│  └─────────────────┬──────────────────────────────────────────┘ │
└────────────────────┼────────────────────────────────────────────┘
                     │ @ObservedObject
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ARCoordinator (Brain)                         │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  @Published State:                                         │ │
│  │  • isReady: Bool                                           │ │
│  │  • statusMessage: String                                   │ │
│  │  • bubbleCount: Int                                        │ │
│  │                                                             │ │
│  │  Core Responsibilities:                                    │ │
│  │  1. ARSession lifecycle (run/pause)                        │ │
│  │  2. Tracking state monitoring (ARSessionDelegate)          │ │
│  │  3. Bubble placement logic                                 │ │
│  │  4. ARWorldMap save/load                                   │ │
│  │  5. Entity management (create/destroy)                     │ │
│  └────────────────┬───────────────────────────────────────────┘ │
└───────────────────┼─────────────────────────────────────────────┘
                    │ session.delegate = self
                    │ weak var arView
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              ARViewContainer (UIViewRepresentable)               │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  • ARView (RealityKit)                                     │ │
│  │  • ARCoachingOverlayView                                   │ │
│  │  • Forwards session to coordinator                         │ │
│  └─────────────────┬──────────────────────────────────────────┘ │
└────────────────────┼────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ARSession (ARKit Core)                        │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Configuration:                                            │ │
│  │  • ARWorldTrackingConfiguration                            │ │
│  │  • sceneReconstruction = .mesh (LiDAR)                     │ │
│  │  • planeDetection = [.horizontal, .vertical]               │ │
│  │  • environmentTexturing = .automatic                       │ │
│  │                                                             │ │
│  │  Outputs (per frame):                                      │ │
│  │  • ARFrame (camera transform, tracking state)              │ │
│  │  • worldMappingStatus                                      │ │
│  │  • Anchors (planes, mesh, custom)                          │ │
│  └─────────────────┬──────────────────────────────────────────┘ │
└────────────────────┼────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   RealityKit Scene Graph                         │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  For each bubble:                                          │ │
│  │  AnchorEntity (world transform)                            │ │
│  │    └─ ModelEntity                                          │ │
│  │         ├─ MeshResource (plane, rounded corners)           │ │
│  │         └─ CustomMaterial                                  │ │
│  │              └─ IridescentSurface.metal shader             │ │
│  └────────────────┬───────────────────────────────────────────┘ │
└────────────────────┼────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│              GPU Rendering Pipeline (Metal)                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Per-pixel shader execution:                               │ │
│  │  1. Read surface normal, view direction, UV                │ │
│  │  2. Compute Fresnel factor                                 │ │
│  │  3. Calculate optical path (thickness variation)           │ │
│  │  4. Map to hue via interference formula                    │ │
│  │  5. Output RGB + opacity + roughness                       │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow: Bubble Placement

```
User taps button
      │
      ▼
ContentView.placeBubble()
      │
      ▼
ARCoordinator.placeBubble()
      │
      ├─→ Get current ARFrame
      ├─→ Extract camera transform
      ├─→ Compute forward vector
      ├─→ Offset position 0.8m
      │
      ├─→ Create BubbleAnchor (Codable)
      │    └─ Save to sessionState.bubbles[]
      │
      └─→ createBubbleEntity(from: BubbleAnchor)
           │
           ├─→ AnchorEntity(world: transform)
           ├─→ MeshResource.generatePlane(...)
           ├─→ CustomMaterial(surfaceShader: "IridescentSurface")
           ├─→ ModelEntity(mesh, materials)
           │
           └─→ arView.scene.addAnchor(anchor)
```

---

## Data Flow: Persistence & Relocalization

### Save (on app background or manual tap)

```
ARCoordinator.saveState()
      │
      ├─→ session.getCurrentWorldMap { map in
      │    └─→ NSKeyedArchiver.archivedData(map)
      │         └─→ write to worldMap.ardata
      │
      └─→ JSONEncoder().encode(sessionState)
           └─→ write to session.json
```

### Load (on app launch)

```
ARCoordinator.loadStateAndRun()
      │
      ├─→ Load worldMap.ardata
      │    └─→ NSKeyedUnarchiver → ARWorldMap
      │         └─→ config.initialWorldMap = map
      │
      ├─→ Load session.json
      │    └─→ JSONDecoder → SessionState
      │         └─→ sessionState.bubbles = [BubbleAnchor]
      │
      └─→ session.run(config)
           │
           └─→ ARKit relocalizes (matches features)
                │
                └─→ On success (trackingState == .normal)
                     └─→ reconstructAllBubbles()
                          └─→ Create entities from saved transforms
```

---

## State Machine: Session Readiness

```
                    ┌─────────────┐
                    │   Startup   │
                    └──────┬──────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  trackingState == .initializing  │
        │  Status: "Initializing..."       │
        │  isReady = false                 │
        └──────┬───────────────────────────┘
               │
               ▼
        ┌──────────────────────────────────┐
        │  trackingState == .limited       │
        │  Reason: .insufficientFeatures   │
        │  Status: "Find textured area"    │
        │  isReady = false                 │
        └──────┬───────────────────────────┘
               │ (user scans environment)
               ▼
        ┌──────────────────────────────────┐
        │  trackingState == .normal        │
        │  BUT worldMappingStatus = .limited│
        │  Status: "Keep scanning..."      │
        │  isReady = false                 │
        └──────┬───────────────────────────┘
               │
               ▼
        ┌──────────────────────────────────┐
        │  trackingState == .normal        │
        │  worldMappingStatus = .mapped    │
        │  Status: "Ready to blow!"        │
        │  ✅ isReady = true               │
        └──────┬───────────────────────────┘
               │
               │ (if tracking degrades)
               ▼
        ┌──────────────────────────────────┐
        │  trackingState == .limited       │
        │  Reason: .excessiveMotion        │
        │  Status: "Move slower"           │
        │  isReady = false                 │
        └──────────────────────────────────┘
```

---

## Module Dependency Graph

```
┌─────────────────────┐
│  BubbleVisionApp    │  (entry point)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   ContentView       │  (SwiftUI)
└──────────┬──────────┘
           │ depends on
           ▼
    ┌──────────────────────┐
    │   ARCoordinator      │
    └──────────┬───────────┘
               │ uses
               ▼
    ┌──────────────────────┐      ┌──────────────────┐
    │  ARViewContainer     │◄─────│  BubbleAnchor    │
    └──────────┬───────────┘      │  (data model)    │
               │                  └──────────────────┘
               ▼
    ┌──────────────────────┐
    │   ARKit              │
    │   RealityKit         │
    └──────────┬───────────┘
               │ renders with
               ▼
    ┌──────────────────────┐
    │  CustomMaterial      │
    │  (IridescentSurface) │
    └──────────────────────┘
```

---

## Session Lifecycle Events

```
Launch App
   │
   ▼
ContentView.onAppear()
   └─→ (if first launch)
       └─→ ARCoordinator.run(in: arView)
   └─→ (if has saved data)
       └─→ ARCoordinator.loadStateAndRun(in: arView)
   │
   ▼
ARSession starts → delegate callbacks begin
   │
   ├─→ session(_:didUpdate:) [every frame]
   │    └─→ Update isReady, statusMessage
   │
   ├─→ sessionWasInterrupted(_:) [phone call, etc.]
   │    └─→ isReady = false
   │
   └─→ sessionInterruptionEnded(_:)
        └─→ Resume (auto)

App Backgrounded
   │
   └─→ scenePhase == .background
        ├─→ ARCoordinator.saveState()
        └─→ ARCoordinator.pause()

App Terminated
   │
   └─→ (iOS auto-saves via scenePhase)
```

---

## Threading Model

| Component | Thread | Notes |
|-----------|--------|-------|
| ARSession callbacks | Background ARKit thread | Must dispatch to main for @Published updates |
| RealityKit rendering | GPU + RealityKit internal | Automatic |
| Metal shader execution | GPU | Per-pixel parallel |
| UI updates (@Published) | Main thread | SwiftUI requires this |
| File I/O (save/load) | Background (async) | getCurrentWorldMap is async |

**Critical:** All `@Published` property updates in ARCoordinator use `DispatchQueue.main.async`

---

## Performance Budget Allocation

```
60 FPS = 16.67ms per frame

Breakdown (target):
├─ ARKit tracking (VIO)          ~5ms   (30%)
├─ Scene reconstruction (LiDAR)  ~2ms   (12%, if enabled)
├─ RealityKit entity updates     ~1ms   (6%)
├─ GPU rendering                 ~6ms   (36%)
│   ├─ Geometry processing       ~1ms
│   ├─ Custom shader execution   ~3ms   (100 bubbles * 0.03ms)
│   └─ Post-processing           ~2ms
└─ App logic + UI                ~2.67ms (16%)

Headroom for spikes              ~1ms
```

**Optimization levers:**
- Reduce bubble cap (100 → 50)
- Simplify shader (remove sin/cos animation)
- Disable scene reconstruction on older devices
- Batch bubble entities (manual instancing)

---

## Error Handling Strategy

| Error Condition | Detection | User Feedback | Recovery |
|-----------------|-----------|---------------|----------|
| Tracking lost | `trackingState != .normal` | Status message: "Move slower" / "Find textured area" | ARCoachingOverlay |
| Mapping incomplete | `worldMappingStatus == .limited` | Status: "Keep scanning..." | Wait for user to scan more |
| Relocalization fails | Timeout after 10s | "Return to original location" | Offer "Start Fresh" button |
| ARWorldMap corrupted | `unarchiver` throws | Silent fallback to fresh session | Log error, delete file |
| Session interrupted | `sessionWasInterrupted` | Status: "Session paused" | Auto-resume via ARKit |
| Out of memory | (rare) system kills app | iOS standard behavior | User relaunches |

---

## Security & Privacy

### Data Stored Locally

```
Documents/
├── worldMap.ardata
│   └── Contains: feature points (3D coords), plane anchors
│   └── Does NOT contain: raw camera frames, identifiable info
│
└── session.json
    └── Contains: bubble transforms (positions), timestamps, UUIDs
    └── Does NOT contain: user data, location
```

### Permissions

- **Camera:** Required, declared in Info.plist
- **Location:** Not used (ARGeoAnchor deferred to V2)
- **Network:** None (no telemetry in MVP)

### User Control

- ARWorldMap never leaves device
- No cloud sync (V1)
- User can delete app → all data removed

---

## Testing Strategy

### Unit Tests (Future)

- `BubbleAnchor` Codable round-trip
- Transform math (forward offset calculation)
- Bubble cap enforcement (max 100)

### Integration Tests

- ARWorldMap save → load → entities match
- Session interruption → resume
- LiDAR detection → mesh occlusion enabled

### Manual QA Matrix

| Scenario | Device | Expected | Status |
|----------|--------|----------|--------|
| First launch, grant camera | iPhone 11 | Coaching overlay → ready | ✅ |
| Place 10 bubbles | iPhone 14 Pro | All visible, 60 FPS | ✅ |
| Background → relaunch | iPad Pro | Relocalize, bubbles restore | ✅ |
| Poor lighting | iPhone XS | Status: "Find better light" | ✅ |
| Fast whip pan | iPhone 13 | Status: "Move slower" | ✅ |
| Outdoor bright sun | iPhone 12 | Tracking maintains | ⚠️ (test) |

---

## Key Design Decisions (Rationale)

### 1. RealityKit over SceneKit

**Reason:** SceneKit soft-deprecated; RealityKit is Apple's future (ECS, visionOS-ready, better AR integration)

**Trade-off:** Requires iOS 15+, but CustomMaterial features need 16+

### 2. ARWorldMap (not ARCollaborationData)

**Reason:** MVP is single-user; world map is simpler (no network layer)

**Trade-off:** Can't share sessions; multi-user requires V2 refactor

### 3. CustomMaterial shader (not PBR textures)

**Reason:** Thin-film iridescence is view-dependent; procedural shader is lightweight and resolution-independent

**Trade-off:** Requires Metal expertise; fallback is generic transparent material

### 4. Button gating on `mapped` + `normal`

**Reason:** Prevents poor UX from unstable tracking; anchors won't hold position if mapping is incomplete

**Trade-off:** User must wait 3-5s on first launch; impatient users may abandon

### 5. 100-bubble cap with FIFO pruning

**Reason:** Prevents performance cliff; draw calls scale linearly

**Trade-off:** Oldest bubbles disappear; user may not notice if they walk away

---

## Future Architecture Considerations (V2+)

### Multi-User (ARCollaborationData)

```diff
+ import MultipeerConnectivity

  ARCoordinator {
+   var mcSession: MCSession
+   func sendCollaborationData()
+   func session(_:didReceive:) // merge remote anchors
  }
```

### Cloud Persistence (iCloud + CloudKit)

```diff
+ import CloudKit

  SessionState {
+   var cloudRecordID: CKRecord.ID?
  }

+ func uploadWorldMap(to: CKContainer)
+ func downloadWorldMap(from: CKRecord)
```

### Ribbon Trails (Mesh Generation)

```diff
  ARCoordinator {
+   var isDrawing: Bool
+   var trailPoints: [simd_float3]
+   func generateRibbonMesh(from: [simd_float3]) -> MeshResource
  }
```

---

## Debugging Tools

### Enable ARKit Debug Options

In `ContentView.swift`:

```swift
.onAppear {
    coordinator.arView?.debugOptions = [
        .showFeaturePoints,      // Yellow dots = VIO features
        .showWorldOrigin,        // Axis gizmo at (0,0,0)
        .showAnchorGeometry,     // Visualize all anchors
        .showStatistics          // FPS counter
    ]
}
```

### Print ARFrame Diagnostics

In `ARCoordinator.swift:session(_:didUpdate:)`:

```swift
print("""
Frame \(frame.timestamp):
  Camera: \(frame.camera.transform.columns.3)
  Tracking: \(frame.camera.trackingState)
  Mapping: \(frame.worldMappingStatus)
  Anchors: \(session.currentFrame?.anchors.count ?? 0)
""")
```

### Inspect Saved Files

Download app container via Xcode:
**Window → Devices → [Device] → Installed Apps → BubbleVision → ⚙️ → Download Container**

---

## Summary

**Core principle:** Separation of concerns via clean boundaries:

- **ContentView:** UI + user intent
- **ARCoordinator:** Business logic + state management
- **ARViewContainer:** ARKit/RealityKit bridge
- **BubbleAnchor:** Pure data (Codable)
- **IridescentSurface:** Pure rendering (stateless shader)

**Result:** Testable, maintainable, and extensible foundation for V2+ features.
