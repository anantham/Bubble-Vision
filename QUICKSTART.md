# Bubble Vision - Quick Start Guide

## 🚀 Build & Run in 3 Steps

### 1. Open in Xcode

```bash
cd "Bubble Vision"
open BubbleVision.xcodeproj
```

### 2. Configure Signing

- Select **BubbleVision** target in Xcode
- Go to **Signing & Capabilities** tab
- Set **Team** to your Apple Developer account
- Xcode will auto-generate a bundle ID if needed

### 3. Run on Device

- **Connect a physical iPhone or iPad** (Simulator won't work for AR)
- Select your device from the scheme menu
- Press **⌘R** to build and run

---

## ✅ What You'll See

1. **First Launch:**
   - Camera permission prompt → tap "Allow"
   - ARCoachingOverlay appears → slowly pan camera to scan environment
   - Status changes from "Scanning..." to "Ready to blow bubbles!"

2. **Place Your First Bubble:**
   - Tap the blue **wind button** at bottom
   - A shimmering rainbow pane appears ~0.8m in front of camera
   - Move around to see iridescence shift with viewing angle

3. **Test Persistence:**
   - Tap "Save Session" or just background the app
   - Kill and relaunch the app
   - After relocalization (~3s), bubbles reappear in same spots

---

## 📱 Device Requirements

**Minimum:**
- iOS 16.0+
- A12 Bionic or later (iPhone XS/XR and up)
- ARKit support

**Recommended for best experience:**
- iPhone 12 Pro or later (LiDAR for real-world occlusion)
- Good lighting (avoid pitch dark or direct sun)
- Textured environment (not blank white walls)

---

## 🐛 Troubleshooting

### "Tracking Limited" / Button Won't Enable

**Cause:** Poor environment or motion too fast

**Fix:**
- Move to a well-lit area with visible details/texture
- Slow down camera motion
- Point at floor/table (not blank wall or window)
- Follow ARCoachingOverlay guidance

### Bubbles Don't Reappear After Relaunch

**Cause:** Relocalization failed (moved to different room, lighting drastically changed)

**Fix:**
- Return to the original room/location where you first scanned
- Point camera at distinctive features ARKit remembers
- Wait 5-10 seconds for relocalization
- If still fails, tap "Save Session" in new location to start fresh map

### Build Errors in Xcode

**Common issues:**

1. **"No signing certificate"**
   - Go to Signing & Capabilities
   - Enable "Automatically manage signing"
   - Select your Team

2. **"Metal shader compilation failed"**
   - Ensure `IridescentSurface.metal` is in Build Phases → Compile Sources
   - Check for typos in shader function name

3. **"Module 'RealityKit' not found"**
   - Set deployment target to iOS 16.0+ (not 15.x)
   - RealityKit CustomMaterial requires iOS 15+, but shader features need 16+

---

## 🎨 Customization Quick Wins

### Change Bubble Size

`ARCoordinator.swift:104` in `placeBubble()`:

```swift
let bubbleData = BubbleAnchor(
    transform: cameraTransform,
    size: SIMD2<Float>(0.8, 0.6)  // width, height in meters
)
```

### Adjust Placement Distance

`ARCoordinator.swift:110`:

```swift
let position = simd_make_float3(cameraTransform.columns.3) + forward * 1.2  // meters
```

### Change Opacity/Color Intensity

`IridescentSurface.metal:60`:

```swift
params.surface().set_opacity(0.5);  // 0.0 = invisible, 1.0 = opaque
```

Or adjust saturation in line 51:

```swift
float3 rainbowColor = hsv2rgb(hue, 0.95, 1.0);  // higher saturation = more vivid
```

---

## 📊 Performance Monitoring

Enable FPS/Stats overlay in `ContentView.swift:21`:

```swift
ARViewContainer(coordinator: coordinator, loadPersisted: loadPersisted)
    .ignoresSafeArea()
    .onAppear {
        coordinator.arView?.debugOptions.insert(.showStatistics)
    }
```

**Target:** 60 FPS on iPhone 12+, 30-45 FPS on iPhone XS/11

---

## 🗂️ File Locations (for debugging)

Persisted data saved to:

```
/var/mobile/Containers/Data/Application/<UUID>/Documents/
├── worldMap.ardata     # ARWorldMap binary
└── session.json        # BubbleAnchor array
```

View in Xcode: **Window → Devices and Simulators → [Your Device] → Installed Apps → BubbleVision → Download Container**

---

## 🚦 Next Steps

Once basic app works:

1. **Add more bubbles** (tap 10-20 times, walk around)
2. **Test in different rooms** (relocalization limits)
3. **Try outdoor** (bright sun stress test)
4. **Experiment with shader params** (color, roughness, animation speed)

Then explore stretch features in README.md roadmap (trails, multi-user, etc.)

---

## 📚 Key Files Reference

| File | Lines | What It Does |
|------|-------|--------------|
| `ARCoordinator.swift` | 43-73 | Session startup, LiDAR detection |
| `ARCoordinator.swift` | 104-126 | Bubble placement math |
| `ARCoordinator.swift` | 182-226 | Tracking state gating logic |
| `IridescentSurface.metal` | 31-61 | Thin-film shader (hue, Fresnel) |
| `ContentView.swift` | 42-69 | UI button + disabled state |

---

**You're all set! 🫧 Happy bubble blowing!**
