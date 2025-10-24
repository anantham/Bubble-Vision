# Bubble Vision - Testing Checklist

## 🎯 Pre-Release Testing Matrix

Use this checklist before shipping to App Store or deploying to beta testers.

---

## Device Coverage

### Minimum (must test)

- [ ] **iPhone XS** (A12, no LiDAR) - minimum supported hardware
- [ ] **iPhone 13** (A15, no LiDAR) - mid-tier
- [ ] **iPhone 14 Pro** (A16, LiDAR) - flagship with mesh occlusion

### Recommended (if available)

- [ ] **iPhone 11** (A13, edge case performance)
- [ ] **iPad Pro 2022** (M2, LiDAR, large screen)

---

## Functional Test Cases

### 1. First Launch Experience

| Test | Steps | Expected Result | Status |
|------|-------|-----------------|--------|
| **Camera permission** | Launch fresh install | Permission prompt appears with clear message | ☐ |
| **Permission granted** | Tap "Allow" | ARCoachingOverlay shows, session starts | ☐ |
| **Permission denied** | Tap "Don't Allow" | Graceful error message (not crash) | ☐ |
| **Coaching overlay** | Follow scan prompts | Status changes to "Ready" within 5-10s | ☐ |

### 2. Bubble Placement

| Test | Steps | Expected Result | Status |
|------|-------|-----------------|--------|
| **Single bubble** | Tap wind button once | Iridescent pane appears ~0.8m forward | ☐ |
| **Multiple bubbles** | Tap 5 times, move around | All 5 bubbles visible in different locations | ☐ |
| **Button disabled state** | Cover camera → button grays | Button disabled, status shows "Tracking limited" | ☐ |
| **Haptic feedback** | Tap button | Medium impact haptic plays | ☐ |

### 3. Visual Quality

| Test | Device | Expected Result | Status |
|------|--------|-----------------|--------|
| **Iridescence shift** | Any | Move around bubble → colors shift smoothly | ☐ |
| **Transparency** | Any | Can see environment through bubble (opacity ~35%) | ☐ |
| **Occlusion (LiDAR)** | Pro model | Walk behind couch → bubble hidden correctly | ☐ |
| **No occlusion (non-LiDAR)** | iPhone 11/13 | Bubble always visible (no occlusion) | ☐ |
| **Smooth animation** | Any | Shimmer effect animates at 60 FPS | ☐ |

### 4. Persistence & Relocalization

| Test | Steps | Expected Result | Status |
|------|-------|-----------------|--------|
| **Auto-save on background** | Place 3 bubbles → home button | App backgrounds without crash | ☐ |
| **Relaunch same room** | Kill app → relaunch in same spot | Bubbles reappear within 3-5s | ☐ |
| **Relaunch different room** | Kill app → move to kitchen → relaunch | Status shows "Relocalizing...", then starts fresh map | ☐ |
| **Manual save button** | Place bubbles → tap "Save Session" | No visible change (silent success) | ☐ |
| **Large session** | Place 50 bubbles → save → reload | All 50 bubbles restore correctly | ☐ |

### 5. Edge Cases & Limits

| Test | Steps | Expected Result | Status |
|------|-------|-----------------|--------|
| **Bubble cap (100)** | Place 105 bubbles | Oldest 5 disappear silently | ☐ |
| **Rapid placement** | Tap button 20 times rapidly | No crashes, all bubbles place correctly | ☐ |
| **Session interruption** | Incoming call during AR | Session pauses, resumes after call | ☐ |
| **Low memory** | Place 100 bubbles on iPhone XS | App doesn't crash (may slow down) | ☐ |

---

## Environmental Stress Tests

### Lighting Conditions

| Environment | Expected Behavior | Status |
|-------------|-------------------|--------|
| **Bright outdoor sun** | Tracking maintains, but may show "Excessive motion" if user moves fast | ☐ |
| **Dim room (evening)** | Coaching overlay prompts "Find better lighting", eventually maps | ☐ |
| **Pitch dark** | Tracking fails gracefully, status: "Insufficient features" | ☐ |
| **Direct sunlight on lens** | Tracking limited, recovers when pointing away | ☐ |

### Surface Types

| Surface | Expected Behavior | Status |
|---------|-------------------|--------|
| **Textured floor (carpet/wood)** | Fast mapping, stable tracking | ☐ |
| **Blank white wall** | Slow mapping, status: "Find textured area" | ☐ |
| **Reflective glass window** | Tracking struggles, coaching overlay persists | ☐ |
| **Mixed (table + floor)** | Maps both planes, bubbles stable | ☐ |

### Motion Patterns

| Motion | Expected Behavior | Status |
|--------|-------------------|--------|
| **Slow pan (recommended)** | Smooth tracking, quick mapping | ☐ |
| **Fast whip (stress test)** | Status: "Move slower", tracking recovers when slowed | ☐ |
| **Walk backward** | Tracking maintains if environment has features | ☐ |
| **Rotate 360° in place** | Mapping improves, bubbles stay anchored | ☐ |

---

## Performance Benchmarks

### Frame Rate (FPS)

| Device | Scenario | Target | Measured | Status |
|--------|----------|--------|----------|--------|
| **iPhone 14 Pro** | 10 bubbles, LiDAR on | ≥60 FPS | _____ | ☐ |
| **iPhone 14 Pro** | 100 bubbles, LiDAR on | ≥45 FPS | _____ | ☐ |
| **iPhone 13** | 10 bubbles, no LiDAR | ≥60 FPS | _____ | ☐ |
| **iPhone 13** | 100 bubbles, no LiDAR | ≥50 FPS | _____ | ☐ |
| **iPhone XS** | 10 bubbles | ≥45 FPS | _____ | ☐ |
| **iPhone XS** | 50 bubbles | ≥30 FPS | _____ | ☐ |

**How to measure:**
1. Enable debug stats: `arView.debugOptions = .showStatistics`
2. Record min/avg FPS over 30 seconds
3. If below target, reduce bubble cap or simplify shader

### Battery Drain

| Test | Steps | Expected | Status |
|------|-------|----------|--------|
| **10-min session** | Place 20 bubbles, walk around for 10 min | ≤10% battery drain | ☐ |
| **Background efficiency** | Background app for 1 hour | Minimal drain (session paused) | ☐ |

### Memory Usage

| Scenario | Expected | Status |
|----------|----------|--------|
| **Fresh launch** | <150 MB | ☐ |
| **100 bubbles placed** | <250 MB | ☐ |
| **After 5 save/load cycles** | No memory leak (stable ~200 MB) | ☐ |

**How to measure:** Xcode → Debug Navigator → Memory graph

---

## User Experience (UX) Tests

### Onboarding Flow

| Step | User Action | Expected Feedback | Status |
|------|-------------|-------------------|--------|
| **1. Launch** | Opens app | Camera permission prompt | ☐ |
| **2. Grant permission** | Taps "Allow" | ARCoachingOverlay appears | ☐ |
| **3. Scan environment** | Points at floor, pans slowly | Overlay shows animated guidance | ☐ |
| **4. Mapping complete** | Scanned ~5m² | Overlay disappears, button turns blue | ☐ |
| **5. Place first bubble** | Taps button | Bubble appears with haptic feedback | ☐ |

### Error Recovery

| Error | Trigger | User Feedback | Recovery | Status |
|-------|---------|---------------|----------|--------|
| **Tracking lost** | Point at blank wall | Status: "Find textured area" | User pans to table → recovers | ☐ |
| **Mapping incomplete** | Try to place bubble too early | Button disabled (gray) | User waits → button turns blue | ☐ |
| **Relocalization fails** | Relaunch in different building | Status: "Return to original location" | User goes back → relocalizes | ☐ |
| **Session interrupted** | Incoming call | Status: "Session paused" | Call ends → auto-resumes | ☐ |

---

## Regression Tests (After Code Changes)

Run these tests after any changes to core files:

### After Modifying `ARCoordinator.swift`

- [ ] Session starts without crash
- [ ] Tracking state gating works (button disabled when limited)
- [ ] Save/load persistence still functional
- [ ] Bubble placement math correct (0.8m forward)

### After Modifying `IridescentSurface.metal`

- [ ] Shader compiles without errors
- [ ] Iridescence effect visible (not solid color)
- [ ] No visual glitches (z-fighting, flickering)
- [ ] Performance unchanged (FPS benchmark)

### After Modifying `ContentView.swift`

- [ ] UI layout correct on all screen sizes
- [ ] Button tap triggers placement
- [ ] Status message updates in real-time
- [ ] Scene phase handling (background/foreground)

---

## Accessibility Tests

| Feature | Test | Expected | Status |
|---------|------|----------|--------|
| **VoiceOver** | Enable VoiceOver → navigate UI | Button labels read aloud | ☐ |
| **Dynamic Type** | Set text size to "Largest" | Status text remains readable | ☐ |
| **Reduce Motion** | Enable in Settings → test app | (MVP: no motion to reduce) | ☐ |

---

## Security & Privacy Tests

| Test | Expected | Status |
|------|----------|--------|
| **Camera usage string** | Info.plist contains clear description | ☐ |
| **No network traffic** | Wireshark shows zero outbound packets | ☐ |
| **Local data only** | All files in Documents/ (no Caches or tmp leaks) | ☐ |
| **Uninstall cleanup** | Delete app → all data removed | ☐ |

---

## App Store Readiness

### Metadata

- [ ] App icon (1024x1024) added to Assets
- [ ] Privacy policy drafted (if collecting any data)
- [ ] Screenshots captured (5.5", 6.5", iPad Pro)
- [ ] App description written (concise, clear value prop)

### Build Configuration

- [ ] Development Team set
- [ ] Bundle ID unique (e.g., `com.yourname.bubblevision`)
- [ ] Deployment target = iOS 16.0
- [ ] Archive builds successfully
- [ ] No compiler warnings

### Compliance

- [ ] Camera usage description is user-friendly
- [ ] No misleading AR content (respects Apple's AR guidelines)
- [ ] No offensive/inappropriate shader effects

---

## Automated Testing (Future)

### Unit Tests (Xcode Test)

```swift
// BubbleAnchorTests.swift
func testCodableRoundTrip() {
    let original = BubbleAnchor(transform: .identity)
    let encoded = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(BubbleAnchor.self, from: encoded)
    XCTAssertEqual(original.id, decoded.id)
}
```

### UI Tests (XCUITest)

```swift
func testPlaceBubble() {
    let app = XCUIApplication()
    app.launch()
    app.buttons["Wind Button"].waitForExistence(timeout: 10)
    XCTAssertTrue(app.buttons["Wind Button"].isEnabled)
    app.buttons["Wind Button"].tap()
    // Assert bubble count label updates
}
```

---

## Test Sign-Off

### MVP Release Criteria

- [ ] All "Minimum" device tests pass
- [ ] No crashes in 30-minute stress test
- [ ] FPS ≥30 on iPhone XS with 50 bubbles
- [ ] Persistence works reliably (5/5 relocalizations)
- [ ] UX errors show helpful messages (not blank/crash)

**Sign-off:**

- Developer: ______________ Date: ______
- QA: ______________ Date: ______

---

## Bug Reporting Template

```markdown
**Device:** iPhone [model]
**iOS Version:** [version]
**App Version:** 1.0 (1)

**Steps to Reproduce:**
1. Launch app
2. [Action]
3. [Action]

**Expected:** [What should happen]
**Actual:** [What actually happened]

**Logs:** (Xcode Console output)
```

**Attach:**
- Screenshot/screen recording
- Xcode console logs
- Memory graph (if crash)

---

## Performance Profiling (Xcode Instruments)

### Time Profiler

**Target:** Identify frame spikes

1. Product → Profile (⌘I)
2. Select "Time Profiler"
3. Record for 60s while placing 20 bubbles
4. Look for hotspots in:
   - `createBubbleEntity`
   - `session(_:didUpdate:)`
   - Metal shader execution

**Pass if:** No single function >5ms per frame

### GPU Frame Capture

**Target:** Verify shader efficiency

1. Debug → Capture GPU Frame (while bubble visible)
2. Inspect `IridescentSurface` shader:
   - Fragment shader execution time
   - Texture bandwidth (should be zero - procedural)
3. Check for overdraw

**Pass if:** Shader <3ms per bubble at 1080p

### Leaks

**Target:** No memory leaks

1. Product → Profile → Leaks
2. Record for 5 min:
   - Place 10 bubbles
   - Save session
   - Background app
   - Relaunch
   - Load session
3. Check for red leaks

**Pass if:** Zero leaks detected

---

## Final Smoke Test (Pre-Ship)

**Do this in one continuous session on a fresh device:**

1. [ ] Install build via TestFlight
2. [ ] First launch → grant camera permission
3. [ ] Place 10 bubbles in living room
4. [ ] Background app
5. [ ] Relaunch → verify bubbles reappear
6. [ ] Place 10 more bubbles
7. [ ] Manually tap "Save Session"
8. [ ] Kill app (swipe up)
9. [ ] Relaunch → verify all 20 bubbles
10. [ ] Move to different room → place 5 more
11. [ ] Return to living room → original 20 still there
12. [ ] Use app for 10 minutes straight → no crashes
13. [ ] Check battery drain → ≤15%

**If all pass → ship it! 🚀**
