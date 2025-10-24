# iPad Wi-Fi Debugging Setup

## Quick Guide: Run Bubble Vision on iPad via Wi-Fi

---

## Prerequisites

✓ iPad and Mac on the **same Wi-Fi network**
✓ iPad running **iOS 16+**
✓ USB cable (for initial setup only)
✓ Xcode open with BubbleVision project

---

## Step 1: Initial USB Connection (One Time Only)

1. **Connect iPad to Mac** using USB cable
2. **Unlock your iPad**
3. iPad shows: **"Trust This Computer?"** → Tap **Trust**
4. Enter your iPad passcode if prompted

---

## Step 2: Enable Network Connection in Xcode

1. In Xcode, go to menu: **Window → Devices and Simulators**
   - Or press **⇧⌘2** (Shift + Command + 2)

2. A window opens with two tabs: **Devices** | Simulators
   - Make sure **Devices** tab is selected

3. In the left sidebar under **iOS**, you'll see your iPad listed:
   ```
   iOS
     📱 Aditya's iPad (connected)
   ```

4. **Click on your iPad** in the left sidebar

5. In the right panel, you'll see device info and a checkbox:
   ```
   ┌────────────────────────────────────────┐
   │ Aditya's iPad                           │
   │ Model: iPad Pro                         │
   │ OS: iOS 18.x                            │
   │                                         │
   │ ☐ Connect via network  ← Check this!   │
   └────────────────────────────────────────┘
   ```

6. **Check the box**: ✓ **Connect via network**

7. Wait ~10 seconds for a **network icon** 🌐 to appear next to your iPad:
   ```
   iOS
     📱 Aditya's iPad 🌐 (connected)
   ```

8. **Disconnect the USB cable** from your iPad

---

## Step 3: Verify Wi-Fi Connection

Your iPad should still appear in the left sidebar with a **network icon** 🌐:

```
iOS
  📱 Aditya's iPad 🌐
```

If you see this, you're ready! ✅

---

## Step 4: Run Bubble Vision on iPad

1. **Close** the Devices window (or leave it open, doesn't matter)

2. Back in the main Xcode window, look at the **top toolbar**:
   ```
   ▶️ [BubbleVision | iPhone 16]  ← Click this device selector
   ```

3. Click the **device selector** (shows current device)

4. A dropdown appears. Select your iPad:
   ```
   iOS Devices
     📱 Aditya's iPad 🌐  ← Select this
   ---
   Simulators
     iPhone 16 Pro
     iPad Pro (12.9-inch)
   ```

5. Press **⌘R** or click the **▶️ Play button**

6. Xcode will:
   - Build the app (~30 seconds first time)
   - Install it wirelessly on your iPad
   - Launch Bubble Vision!

---

## Troubleshooting

### "iPad Not Showing Up in Device List"

**Check:**
- ✓ iPad and Mac on **same Wi-Fi** (not cellular, not different networks)
- ✓ iPad is **unlocked**
- ✓ iPad **Bluetooth is ON** (Settings → Bluetooth)
- ✓ Mac **Bluetooth is ON** (System Settings → Bluetooth)

**Fix:**
1. Go back to **Window → Devices and Simulators**
2. Uncheck and re-check **"Connect via network"**
3. Or reconnect USB cable temporarily, then disconnect

---

### "Network Icon Doesn't Appear"

**Wait:** It can take up to 30 seconds for the 🌐 icon to show up

**If still missing:**
1. Make sure iPad and Mac are on **same Wi-Fi network**
2. On iPad: **Settings → General → About** → Scroll to **Wi-Fi Address**
   - Note the IP (e.g., 192.168.1.45)
3. On Mac, verify you're on same subnet:
   - System Settings → Wi-Fi → Details → IP Address
   - Should start with same numbers (e.g., 192.168.1.x)

---

### "Build Succeeded but App Doesn't Launch"

**First time only:** You need to trust the developer certificate on iPad

1. On iPad, go to: **Settings → General → VPN & Device Management**
2. Under **Developer App**, tap your Apple ID
3. Tap **Trust "Your Name"**
4. Confirm by tapping **Trust**

Now run the app again from Xcode!

---

### "App Installed but Shows White Screen / Crashes"

**This is normal for AR apps on first launch!**

The app needs camera permission:

1. iPad shows: **"Bubble Vision Would Like to Access the Camera"**
2. Tap **Allow**
3. App should now show AR view with coaching overlay

If you accidentally tapped "Don't Allow":
- Go to iPad **Settings → Bubble Vision → Camera** → Turn ON

---

### "iPad Shows as Unavailable / Preparing"

**Wait:** Xcode is syncing symbols (~2 minutes first time)

You'll see:
```
📱 Aditya's iPad (preparing...)
```

Let it finish. Status will change to:
```
📱 Aditya's iPad 🌐
```

---

### "Cannot Run on iPad - Requires A12 or Later"

**Check your iPad model:**

Supported:
- ✅ iPad Pro (2018 and later)
- ✅ iPad Air (3rd gen and later)
- ✅ iPad mini (5th gen and later)
- ✅ iPad (8th gen and later)

Not supported:
- ❌ iPad mini 4 or older
- ❌ iPad Air 2 or older
- ❌ iPad (7th gen or older)

**Reason:** Bubble Vision requires ARKit, which needs A12 processor minimum

---

## Wi-Fi Debugging Tips

### Keep iPad Awake
- Go to iPad **Settings → Display & Brightness → Auto-Lock** → Set to **Never** (while developing)
- This prevents Wi-Fi from sleeping

### Speed Up Builds
- Use **Debug** configuration (default)
- Don't use **Release** until you're shipping

### If Connection Drops
- iPad went to sleep → Unlock it and wait 10 seconds
- Changed Wi-Fi network → Reconnect to same network as Mac
- Mac went to sleep → Wake Mac, wait for iPad to reconnect

### Re-enable Wi-Fi After Mac Restart
- Wi-Fi debugging stays enabled! No need to reconfigure
- Just make sure both devices are on same network

---

## Alternative: Xcode Cloud / TestFlight (No Cable Ever)

If you want to avoid cables entirely even for setup:

### TestFlight Method (For Distribution)

1. Archive the app in Xcode
2. Upload to App Store Connect
3. Add your iPad to TestFlight internal testing
4. Install from TestFlight app on iPad

**Downside:** Slower iteration (each build takes ~10 min to upload/process)

**When to use:** For beta testing with others, or final testing before release

---

## Quick Reference

| Task | Command |
|------|---------|
| Open Devices window | **Window → Devices and Simulators** or **⇧⌘2** |
| Change target device | Click device selector (top toolbar) |
| Build & Run | **⌘R** |
| Stop running app | **⌘.** (Command + Period) |

---

## Checklist: First Time Setup

- [ ] iPad connected via USB
- [ ] iPad unlocked and trusted computer
- [ ] Opened **Window → Devices and Simulators** in Xcode
- [ ] Selected iPad in left sidebar
- [ ] Checked ✓ **"Connect via network"**
- [ ] Saw network icon 🌐 appear next to iPad
- [ ] Disconnected USB cable
- [ ] iPad still showing with 🌐 in device list
- [ ] Selected iPad in device selector (top of Xcode)
- [ ] Pressed ⌘R to build and run
- [ ] App appeared on iPad
- [ ] Allowed camera permission on iPad
- [ ] Saw AR coaching overlay

**All checked? You're good to go! 🎉**

---

## What Happens When You Press ⌘R

1. **Xcode compiles** Swift code → binary
2. **Xcode links** frameworks (ARKit, RealityKit, Metal)
3. **Xcode signs** the app with your certificate
4. **Xcode sends** the app to iPad over Wi-Fi
5. **iPad installs** the app (you'll see progress on iPad screen)
6. **iPad launches** Bubble Vision
7. **Xcode debugger** attaches (you see logs in Xcode console)

---

## Expected First Run Experience

1. iPad screen goes black briefly
2. App icon appears on home screen
3. App opens (black screen for ~2 seconds)
4. **Camera permission dialog** appears → Tap **Allow**
5. **AR coaching overlay** appears (animated circle)
6. Status at top: **"Scanning environment..."**
7. Point iPad at floor or table
8. Status changes to: **"Ready to blow bubbles!"**
9. Blue **wind button** becomes enabled
10. Tap button → iridescent bubble appears! 🫧

---

## Performance on iPad

| iPad Model | LiDAR? | Expected FPS | Occlusion |
|------------|--------|--------------|-----------|
| iPad Pro 2018 | ❌ | 45-60 | No |
| iPad Pro 2020+ | ✅ | 60 | Yes |
| iPad Air 5th gen | ❌ | 50-60 | No |
| iPad mini 6th gen | ❌ | 45-55 | No |

**LiDAR models:** iPad Pro 11" (2020+), iPad Pro 12.9" (2020+)

---

## Ready to Test!

Your setup is complete. From now on:

1. Make sure iPad and Mac on same Wi-Fi
2. Select iPad in Xcode device selector
3. Press ⌘R

**No cable needed!** ✨

---

## Next: Testing Bubble Vision

Once the app launches:

1. **Grant camera permission** when prompted
2. **Follow coaching overlay** (scan floor/table)
3. **Wait for "Ready to blow bubbles!"**
4. **Tap wind button** 🌪️
5. **Move around** to see iridescent colors shift
6. **Tap "Save Session"** then close app
7. **Relaunch** → bubbles should reappear in same spots!

See **TESTING.md** for full test checklist.

---

**Happy bubble blowing! 🫧**
