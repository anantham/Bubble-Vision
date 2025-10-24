# Xcode Setup Guide - Step by Step with Screenshots

**Problem:** Can't find "Signing & Capabilities" tab in Xcode

**Solution:** You need to select the project target first!

---

## The Issue

When you first open Xcode, it usually shows you **code files** in the center. The Signing & Capabilities settings are hidden until you tell Xcode you want to see **project settings** instead of code.

---

## Step-by-Step Solution

### Step 1: Find the Project Navigator (Left Sidebar)

**Where to look:** The leftmost panel in Xcode

You should see a list of files and folders. At the very top is:

```
🔷 BubbleVision          ← Blue app icon
  📁 BubbleVision        ← Folder
    BubbleVisionApp.swift
    Models/
    AR/
    Views/
    Shaders/
    Assets.xcassets
  🎯 BubbleVision         ← Target (under TARGETS section)
```

**Can't see the sidebar?**
- Press **⌘0** (Command + Zero) to toggle the Navigator
- Or go to **View → Navigators → Show Project Navigator**

---

### Step 2: Click the Blue Project Icon

**What to click:** The **blue app icon** 🔷 at the very top that says "BubbleVision"

**What happens:** The center area changes from showing code to showing a table with two sections:
- **PROJECT** (has one item: BubbleVision)
- **TARGETS** (has one item: BubbleVision)

---

### Step 3: Click "BubbleVision" Under TARGETS

**Important:** Click the one under **TARGETS**, not PROJECT!

```
PROJECT
  BubbleVision          ← Don't click this

TARGETS
  BubbleVision          ← Click THIS one!
```

The selected item will be **highlighted in blue**.

---

### Step 4: Look for the Tab Bar

**Where to look:** At the top of the center editor area

You'll now see a row of tabs:

```
┌───────────────────────────────────────────────────────────┐
│  General  │ Signing & Capabilities │ Resource Tags │ Info │
│           │  ← CLICK HERE!         │               │      │
└───────────────────────────────────────────────────────────┘
```

Click **"Signing & Capabilities"**

---

### Step 5: Set Your Team

You'll see something like:

```
┌──────────────────────────────────────────────────────────┐
│ Signing & Capabilities                                    │
├──────────────────────────────────────────────────────────┤
│                                                            │
│ ⚠️ Signing for "BubbleVision" requires a development team │
│                                                            │
│ ✓ Automatically manage signing                            │
│                                                            │
│ Team:  [None ▼]  ← Click this dropdown                    │
│                                                            │
│ Bundle Identifier: com.bubblevision.app                   │
│                                                            │
└──────────────────────────────────────────────────────────┘
```

**Click the "Team" dropdown** and select:

- **Your Apple ID** (shows as "Your Name (Personal Team)")
- OR click **"Add Account..."** if you haven't logged in yet

---

## If You Need to Add Your Apple ID

1. Click **"Add Account..."** in the Team dropdown
2. A window pops up → Click **"Continue"**
3. Sign in with your **Apple ID** (the one you use for iCloud/App Store)
4. After signing in, go back to the **Team** dropdown
5. Select your newly added account

**Note:** You do NOT need a paid Apple Developer account ($99/year) for local testing. A free personal team works fine!

---

## How to Know It Worked

✅ **Success indicators:**

1. The ⚠️ warning disappears
2. You see: **"Signing Certificate: Apple Development"**
3. No red errors in the Signing section

---

## Troubleshooting

### "I don't see PROJECT and TARGETS sections"

**Fix:** You probably have a **code file** selected in the navigator instead of the project.

1. Scroll to the very top of the left sidebar
2. Click the **blue icon** 🔷 that says "BubbleVision"

---

### "I clicked it but I only see PROJECT, not TARGETS"

**Fix:** Make sure you clicked the **project icon** (blue), not a folder or file.

The item you click should be at the **very top** of the navigator, above all folders.

---

### "The tabs only show Info, Build Settings, Build Phases"

**Fix:** You clicked the item under **PROJECT** instead of **TARGETS**.

Scroll down in the center area to find the **TARGETS** section and click the "BubbleVision" listed there.

---

### "Team dropdown is empty / only shows 'Add Account'"

**Fix:** You need to sign in with your Apple ID.

1. Click **"Add Account..."**
2. Sign in with your Apple ID
3. After signing in, select your account in the Team dropdown

---

### "I added my account but it still shows an error"

**Fix:** Make sure "Automatically manage signing" is **checked** ✓

If it is and you still see errors, try:
1. **Uncheck** "Automatically manage signing"
2. **Check** it again
3. Xcode will regenerate certificates

---

## Quick Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Show/Hide Navigator (left sidebar) | **⌘0** |
| Show Project Settings | **⌘1** then click project icon |
| Build & Run | **⌘R** |

---

## Visual Checklist

Follow this checklist in order:

- [ ] Xcode is open
- [ ] Left sidebar is visible (if not, press ⌘0)
- [ ] I can see a blue icon 🔷 at the top of the sidebar
- [ ] I clicked that blue icon
- [ ] Center area shows "PROJECT" and "TARGETS" sections
- [ ] I clicked "BubbleVision" under **TARGETS** (it's highlighted in blue)
- [ ] I see tabs: General, Signing & Capabilities, etc.
- [ ] I clicked the "Signing & Capabilities" tab
- [ ] I see the Team dropdown
- [ ] I selected my Apple ID in the Team dropdown
- [ ] The ⚠️ warning is gone
- [ ] I see "Signing Certificate: Apple Development"

**If all checked → You're ready to build! 🎉**

---

## Next Steps After Signing

1. **Connect your iPhone** via USB
2. **Unlock your iPhone** and trust the computer if prompted
3. At the top of Xcode, next to the ▶️ button, click the **device selector**
4. Choose your **iPhone** (not "Any iOS Device" or Simulator)
5. Press **⌘R** or click the ▶️ **Play button**

Xcode will compile and install the app on your iPhone!

---

## Still Stuck?

Take a screenshot of your Xcode window and I can help you identify what to click!

**Most common issue:** People click a folder or file instead of the project icon. Make sure you click the **very first item** at the top of the navigator that has a blue app icon 🔷.

---

## Alternative Method (If Above Doesn't Work)

Try this menu-based approach:

1. In Xcode, go to the top menu: **View → Navigators → Show Project Navigator**
2. Then: **Editor → Show Inspectors → Show File Inspector** (⌘⌥1)
3. Click on the blue **BubbleVision** icon in the left sidebar
4. The center area should now show project settings

---

## Video-Style Walkthrough (Text)

```
You: Opens BubbleVision.xcodeproj
Xcode: Shows code files

You: Look at left sidebar
Xcode: Shows file tree with 🔷 BubbleVision at top

You: Click that blue BubbleVision icon
Xcode: Center area changes to show PROJECT and TARGETS table

You: Scroll down to TARGETS section
Xcode: See "BubbleVision" listed under TARGETS

You: Click "BubbleVision" under TARGETS
Xcode: Item highlights in blue, tabs appear at top

You: See tabs: General | Signing & Capabilities | ...
Xcode: Tabs are visible

You: Click "Signing & Capabilities"
Xcode: Shows signing settings with Team dropdown

You: Click "Team" dropdown
Xcode: Shows "None", "Add Account...", and your Apple IDs

You: Select your Apple ID
Xcode: Warning disappears, signing configured! ✅
```

---

**You're now ready to build Bubble Vision! 🫧**

Connect your iPhone and press **⌘R**!
