# Bubble Vision - Quick Reference Card

**Print or bookmark this for fast lookups during development**

---

## 🔥 Critical File Locations

| Task | File | Line |
|------|------|------|
| **Session startup** | `ARCoordinator.swift` | 43-73 |
| **Placement logic** | `ARCoordinator.swift` | 104-126 |
| **Tracking state** | `ARCoordinator.swift` | 182-226 |
| **Shader code** | `IridescentSurface.metal` | 31-61 |
| **UI button** | `ContentView.swift` | 42-69 |
| **Persistence** | `ARCoordinator.swift` | 87-102 |
| **Camera permission** | `Info.plist` | 7-8 |

---

## ⚡ Common Tasks (Copy-Paste)

### Build & Run

```bash
open BubbleVision.xcodeproj
# Set Team → Connect device → ⌘R
```

### Enable Debug Visualizations

In `ContentView.swift`, add to `.onAppear`:

```swift
coordinator.arView?.debugOptions = [
    .showFeaturePoints,    // Yellow dots
    .showWorldOrigin,      // Axis at (0,0,0)
    .showStatistics        // FPS counter
]
```

### Print ARFrame Info

In `ARCoordinator.swift:session(_:didUpdate:)`:

```swift
print("Tracking: \(frame.camera.trackingState), Mapping: \(frame.worldMappingStatus)")
```

### Adjust Bubble Size

`ARCoordinator.swift:115`:

```swift
size: SIMD2<Float>(0.8, 0.6)  // width, height (meters)
```

### Change Placement Distance

`ARCoordinator.swift:110`:

```swift
+ forward * 1.2  // meters from camera
```

### Tweak Shader Opacity

`IridescentSurface.metal:59`:

```swift
params.surface().set_opacity(0.5);  // 0.0-1.0
```

### Change Bubble Cap

`ARCoordinator.swift:25`:

```swift
private let maxBubbles = 50  // default: 100
```

---

## 🐛 Common Errors & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| **"No signing identity"** | Team not set | Target → Signing → Select Team |
| **"Metal shader failed"** | Shader not in build | Add `IridescentSurface.metal` to Compile Sources |
| **Button won't enable** | Poor tracking | Point at textured surface, slow motion |
| **Bubbles don't restore** | Different room | Return to original scan location |
| **Black screen** | Camera permission denied | Settings → BubbleVision → Camera → Allow |
| **Low FPS** | Too many bubbles | Reduce cap or simplify shader |

---

## 📱 Device Requirements

| Feature | Minimum | Recommended |
|---------|---------|-------------|
| **Basic AR** | A12+ (XS/XR) | A13+ (11 Pro) |
| **Occlusion** | LiDAR (12 Pro+) | 14 Pro+ |
| **iOS** | 16.0 | Latest |

---

## 🎨 Shader Parameters

| Parameter | Location | Default | Range |
|-----------|----------|---------|-------|
| **Hue seed** | `BubbleAnchor.swift:11` | Random | 0.0-1.0 |
| **Opacity** | `IridescentSurface.metal:59` | 0.35 | 0.0-1.0 |
| **Roughness** | `IridescentSurface.metal:58` | 0.1+fresnel | 0.0-1.0 |
| **Shimmer speed** | `IridescentSurface.metal:45` | `time*0.5` | Adjust multiplier |

---

## 🔧 Performance Tuning

### FPS < 30? Try:

1. **Reduce bubble cap:**
   ```swift
   private let maxBubbles = 50
   ```

2. **Disable scene reconstruction (non-LiDAR):**
   ```swift
   // Comment out in ARCoordinator.swift:48-51
   // config.sceneReconstruction = .mesh
   ```

3. **Simplify shader:**
   ```metal
   // Remove sin/cos in IridescentSurface.metal:45-47
   float thickness = 400.0;  // Static thickness
   ```

---

## 📊 Instrumentation

### Profile with Xcode

```
Product → Profile (⌘I)
├─ Time Profiler   → CPU hotspots
├─ GPU Frame       → Shader performance
├─ Leaks           → Memory issues
└─ Allocations     → Memory growth
```

### Monitor FPS

```swift
arView.debugOptions = .showStatistics
```

### Check Memory

**Xcode → Debug Navigator → Memory**

Target: <250 MB with 100 bubbles

---

## 🧪 Quick Smoke Test

1. Launch → grant camera
2. Scan floor (5 seconds)
3. Button turns blue
4. Tap → bubble appears
5. Move around → iridescence shifts
6. Background app
7. Relaunch → bubbles restore

**Pass = No crashes, bubbles in same spots**

---

## 📂 Data Locations

**On device:**

```
Documents/
├── worldMap.ardata   (ARWorldMap binary)
└── session.json      (Bubble transforms)
```

**Download via Xcode:**

Window → Devices → [Device] → Apps → BubbleVision → ⚙️ → Download Container

---

## 🚦 Session States

```
.notAvailable    → "Tracking unavailable"
.initializing    → "Initializing..."
.limited(reason) → "Move slower" / "Find textured area"
.normal          → ✅ Ready (if mapped)
```

**Check in:** `ARCoordinator.swift:session(_:didUpdate:)`

---

## 🎯 Tracking Quality

| Condition | State | Status Message |
|-----------|-------|----------------|
| **Good light + texture** | `.normal` + `.mapped` | "Ready to blow!" ✅ |
| **Blank wall** | `.limited(.insufficientFeatures)` | "Find textured area" |
| **Too dark** | `.limited(.insufficientFeatures)` | "Find better lighting" |
| **Fast motion** | `.limited(.excessiveMotion)` | "Move slower" |
| **Just started** | `.limited(.initializing)` | "Initializing..." |

---

## 🔑 Key Classes

| Class | Purpose | Pattern |
|-------|---------|---------|
| `ARCoordinator` | AR session manager | Coordinator |
| `BubbleAnchor` | Data model | Codable struct |
| `ContentView` | UI layer | SwiftUI View |
| `ARViewContainer` | RealityKit bridge | UIViewRepresentable |
| `IridescentSurface` | GPU shader | Metal function |

---

## 📐 Math Reference

### Forward Vector (Camera Space)

```swift
let forward = -transform.columns.2  // Negative Z axis
```

### World Position Offset

```swift
let newPos = cameraPos + forward * distance
```

### Transform Matrix

```
simd_float4x4 = [
  right   (X axis),
  up      (Y axis),
  -forward (Z axis),
  position (translation)
]
```

---

## 🎛️ Configuration Toggles

### Enable Plane Detection

`ARCoordinator.swift:54`:

```swift
config.planeDetection = [.horizontal, .vertical]
```

### Enable Mesh Occlusion (LiDAR)

`ARCoordinator.swift:48-51`:

```swift
if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
    config.sceneReconstruction = .mesh
}
```

### Enable Environment Texturing

`ARCoordinator.swift:46`:

```swift
config.environmentTexturing = .automatic
```

---

## 🎨 Color Customization

### Change Base Hue

`IridescentSurface.metal:53`:

```metal
float hue = fract(...) + 0.3;  // Shift by 0.3 (green → red)
```

### Adjust Saturation

`IridescentSurface.metal:51`:

```metal
float3 rainbowColor = hsv2rgb(hue, 0.95, 1.0);  // 0.0=gray, 1.0=vivid
```

### Add Milky Tint

`IridescentSurface.metal:54`:

```metal
float3 baseColor = mix(rainbowColor, float3(1.0), 0.2);  // More white
```

---

## 🔄 Lifecycle Hooks

| Event | Method | Action |
|-------|--------|--------|
| **App launch** | `ContentView.onAppear()` | Start/load session |
| **Background** | `scenePhase == .background` | Save + pause |
| **Foreground** | `scenePhase == .active` | Resume (auto) |
| **Interruption** | `sessionWasInterrupted()` | isReady = false |
| **Resume** | `sessionInterruptionEnded()` | Wait for tracking |

---

## 🆘 Emergency Debugging

### Session Won't Start?

```swift
print(ARWorldTrackingConfiguration.isSupported)  // Must be true
```

### Shader Not Applying?

```swift
// In createBubbleEntity, check:
print("CustomMaterial created: \(material is CustomMaterial)")
```

### Relocalization Failing?

```swift
// In session(_:didUpdate:):
print("Anchors: \(session.currentFrame?.anchors.count ?? 0)")
print("Mapping: \(frame.worldMappingStatus.rawValue)")
```

### Memory Leak?

```
Product → Profile → Leaks
Record for 5 min → Check for red bars
```

---

## 📞 Where to Get Help

| Issue | Resource |
|-------|----------|
| **Build errors** | `QUICKSTART.md` § Troubleshooting |
| **AR concepts** | `ARCHITECTURE.md` |
| **Testing** | `TESTING.md` |
| **Gemini roadmap** | Original ARKit doc (in prompt) |
| **Apple docs** | developer.apple.com/arkit |

---

## ✅ Pre-Ship Checklist

- [ ] No compiler warnings
- [ ] Smoke test passed (above)
- [ ] FPS ≥30 on iPhone XS
- [ ] Persistence works (5/5 relocalizations)
- [ ] App icon added (1024×1024)
- [ ] Camera usage string clear
- [ ] Bundle ID unique
- [ ] Team set in Signing

---

## 🎓 Key Learnings

1. **Always gate on tracking + mapping** → Better UX than random failures
2. **ARWorldMap is fragile** → Same room, same lighting works best
3. **LiDAR = premium feature** → Design for graceful degradation
4. **CustomMaterial = power + complexity** → Fallback to SimpleMaterial
5. **Session delegate = main thread** → Use `DispatchQueue.main.async`

---

**Print this page and keep it next to your monitor! 📌**
