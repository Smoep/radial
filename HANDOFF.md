# Radial — Lessons Learned & Handover

A comprehensive reference for maintaining Radial.
Everything we learned building Radial — what worked, what didn't, and why.

---

## Table of Contents

1. [What Radial Is](#1-what-radial-is)
2. [UX Principles — What We Got Right](#2-ux-principles)
3. [Architecture & Code Patterns](#3-architecture--code-patterns)
4. [macOS System Integration](#4-macos-system-integration)
5. [SwiftUI + @Observable Performance](#5-swiftui--observable-performance)
6. [Overlay / Floating Window Rendering](#6-overlay--floating-window-rendering)
7. [Input Capture — Trackpad via Private Frameworks](#7-input-capture)
8. [Action Execution](#8-action-execution)
9. [Persistence & Settings](#9-persistence--settings)
10. [Editor UI Patterns](#10-editor-ui-patterns)
11. [Build & Deploy](#11-build--deploy)
12. [Mistakes Made & How We Fixed Them](#12-mistakes-made)
13. [Unfixed / Known Remaining Issues](#13-unfixed--remaining-issues)
14. [Reusable Components](#14-reusable-components)
15. [Quick Reference: Key Codes & Constants](#15-quick-reference)

---

## 1. What Radial Is

A macOS radial action launcher activated by **touch-and-hold** on the trackpad.

**Flow**: Touch trackpad → loading ring appears → hold threshold met → radial pie
menu appears at cursor → slide finger to select category → enter sub-ring →
lift/click to execute action.

**Key insight**: The user's finger never leaves the trackpad. Zero mouse movement
required. The entire interaction — from activation to action — happens in one
continuous gesture.

---

## 2. UX Principles

### 2.1 Minimize Mouse Movement
The #1 design rule. Users should never have to move the mouse at all.
- Overlay appears at cursor position (wherever it happens to be)
- Selection is radial — finger slides from center outward
- No targeting distant UI elements

### 2.2 Touch-and-Hold Activation with Visual Feedback
- Candidate ring (yellow progress arc) appears immediately on finger-down
- Fills over the configurable hold duration (default 0.6s)
- Users NEED to see this progress — without it, the hold feels broken
- If finger moves >3pt during hold → cancel (they're using trackpad normally)
- Ring delay (default 0.25s) prevents flash on quick taps

### 2.3 Two Selection Modes
- **Lift-to-select** (default): Lift finger while hovering over item → execute
- **Click-to-select**: Finger lift keeps overlay open, tap to confirm
- Lift-to-select is faster; click-to-select is more forgiving for new users

### 2.4 Radial > Grid Layout
We started with a grid and moved to radial. Radial is better because:
- Equal angular distance from center to any slice (Fitts's Law)
- Categories in inner ring, actions in outer ring — natural hierarchy
- Supports recursive subcategories at unlimited depth
- Fixed arc-width per item keeps things readable at any depth

### 2.5 Drag-and-Drop Everywhere
- Editor supports drag-to-reorder for categories, actions, and subcategories
- Within any level — `onMove` + `moveAction(atParentPath:from:to:)`
- Recursive data model makes this possible at any depth
- Spring animation on drag for tactile feel

### 2.6 Click Row to Edit (No Extra Buttons)
- Originally had pencil edit buttons on each row — too many targets
- Clicking the row itself opens the editor sheet
- Consistent: categories, actions, and subcategories all work the same way
- Different sheet types per item type (category vs action vs subcategory)

### 2.7 Center = Cancel
- The dead zone at center (r < 38pt) is always "cancel"
- Shows `✕` hint after reveal animation completes
- Clicking back to center lets user abort without executing

### 2.8 Glass Aesthetic (macOS 26)
- `.glassEffect(in: RoundedRectangle(...))` for settings sections
- Overlay slices: dark base (`Color(white: 0.10, opacity: 0.55)`) + tinted color
  overlay + white specular + border stroke
- Selected slice: brighter tint + blur glow + thicker border
- This looks native on macOS 26, trashy on older versions

### 2.9 Keep App Running in Background
- `applicationShouldTerminateAfterLastWindowClosed` returns `false`
- Menu bar icon always accessible — "Radial Settings" to reopen window
- User closes settings, app keeps listening on trackpad

---

## 3. Architecture & Code Patterns

### 3.1 Component Hierarchy

```
RadialApp.swift            App entry + menu bar + dock icon
  └─ ContentView.swift     Settings UI (ScrollView + sliders + editor)
       └─ SessionEngine    Central coordinator (created as @State)
            ├─ AppSettings        User preferences (singleton)
            ├─ TrackpadService    Input layer (multitouch + CGEventTap)
            ├─ SelectionOverlay   Floating NSWindow with Canvas
            └─ RadialMenuStore    Menu data model (singleton, JSON in UserDefaults)
```

### 3.2 Polling Architecture (Timer-Based)

SessionEngine runs a 16ms Timer (`1/60s`) that:
1. Reads trackpad state (touch position, phase, clicks)
2. Converts screen coordinates to radial (angle + radius)
3. Walks the menu tree to find the hovered item
4. Updates `@Observable` properties (with delta guards)
5. Triggers overlay show/hide/redraw

**Why polling, not events**: We tried event-driven. It's faster to reason about
when a single tick reads all state, computes all derived values, and writes once.
No race conditions between multitouch callbacks and CGEvent callbacks.

### 3.3 State Machine: idle → candidate → active

```
idle:        No finger on trackpad
candidate:   Finger down, hold timer counting (shows loading ring)
active:      Hold threshold met, overlay showing, tracking selection
```

Transitions:
- `idle → candidate`: Single finger touches trackpad (MT callback, 0→1 fingers)
- `candidate → idle`: Finger moves >3pt, finger lifts, click occurs, multi-finger
- `candidate → active`: Hold timer fires (after `activationHoldDuration`)
- `active → idle`: Action executed (lift or click finalize) + cooldown period

### 3.4 Radial Selection Model

Selection state is a **path** through the menu tree:
```swift
selectionPath: [Int] = []     // e.g. [2, 0, 1] = category 2, action 0, sub-action 1
lockedDepth: Int = 0          // how many rings are "locked" (finger moved outward)
```

Ring detection: compare `fingerRadius` against ring boundaries (`ringInnerRadius`/
`ringOuterRadius` at each depth). Angle detection: compare `fingerAngle` against
slice boundaries at the detected depth.

### 3.5 Recursive Menu Data Model

```swift
struct RadialAction: Codable, Identifiable {
    var id: String
    var label: String
    var systemImage: String
    var actionType: ActionType
    var actionConfig: ActionConfig
    var children: [RadialAction]?     // nil = executable, non-nil = subcategory

    var isSubcategory: Bool { children != nil }  // NOT children.isEmpty!
}
```

**Critical**: `isSubcategory` checks `children != nil`, NOT `!(children ?? []).isEmpty`.
An empty subcategory (folder with no actions yet) must still be treated as a folder.

### 3.6 Path-Based CRUD Operations

The store provides path-based access into the recursive tree:
```swift
func actionAt(path: [Int]) -> RadialAction?
func setAction(_ action: RadialAction, at path: [Int])
func removeAction(at path: [Int])
func appendAction(_ action: RadialAction, at path: [Int])
func moveAction(atParentPath: [Int], from: IndexSet, to: Int)
```

This lets the editor work at any nesting depth without special-casing.

---

## 4. macOS System Integration

### 4.1 Accessibility Permissions

**CRITICAL**: The app needs Accessibility access for CGEventTap (input capture)
and CGEvent posting (keyboard shortcuts). Permissions are tied to the **bundle ID**.

```swift
// Check and prompt in the UI
if !AXIsProcessTrusted() {
    let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
}
```

**NEVER change the bundle ID** after the user grants permissions — they'd have to
re-grant in System Preferences.

**NEVER codesign** after deploying to `/Applications/` — it invalidates the
accessibility permission. The app gets a new code identity and macOS treats it as
a different app.

### 4.2 Menu Bar Status Item

```swift
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
button.image = NSImage(systemSymbolName: "hand.draw.fill", ...)
button.image?.isTemplate = true  // adapts to light/dark menu bar
```

Menu items: "App Settings" (opens window) + "Quit".

### 4.3 Menu-Bar-Only App (No Dock Icon) — Preferred Pattern

The lightest possible macOS utility: lives exclusively in the menu bar, never
appears in the Dock or the ⌘-Tab app switcher. This is what Radial uses.

**Step 1 — Info.plist key** (or Build Setting `Application is agent (UIElement)`):
```
LSUIElement = YES
```
This single flag removes the Dock icon, hides the app from ⌘-Tab, and stops
macOS from managing it as a regular foreground application.

**Step 2 — SwiftUI `MenuBarExtra` scene** (replaces legacy `NSStatusItem`):
```swift
@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()   // SwiftUI menu contents
        } label: {
            Image(systemName: "hand.draw.fill")
                .imageScale(.medium)
        }
    }
}
```
No `Window` or `Settings` scene — the settings window is created on-demand
from AppDelegate so it's not allocated until the user actually opens it.

**Step 3 — Keep app alive after settings window closes**:
```swift
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
}
```

**Step 4 — Lazy settings window** (created only when first needed):
```swift
func showSettings() {
    if settingsWindow == nil || !settingsWindow!.isVisible {
        let controller = NSHostingController(rootView: ContentView())
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

**Why this is lighter**:
- No Dock tile = no Dock process overhead
- No app switcher slot
- Settings window NSHostingController not allocated until first open
- No SwiftUI `WindowGroup` / `Settings` scene keeping a view hierarchy alive

### 4.4 Window Management

```swift
// Keep app alive after window close
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
}

// Reopen settings window from menu bar
NSApplication.shared.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)
```

Find the main window by title or identifier:
```swift
NSApp.windows.first(where: { $0.title == "Radial" || $0.identifier?.rawValue.contains("main") == true })
```

---

## 5. SwiftUI + @Observable Performance

### 5.1 Delta-Guard ALL Property Writes

The biggest performance lesson. `@Observable` triggers view updates on EVERY write,
even if the value didn't change. In a 60fps polling loop, this causes massive waste.

```swift
// BAD — triggers redraw 60 times/second even when finger is still
fingerRadius = pixelDist

// GOOD — only triggers when value actually changed meaningfully
if abs(pixelDist - fingerRadius) > 0.5 { fingerRadius = pixelDist }
if abs(cwAngle - fingerAngle) > 0.005 { fingerAngle = cwAngle }
if newZoneID != liveZoneID { liveZoneID = newZoneID }
```

**Thresholds used**:
- Position/radius: `> 0.5` (half a point — invisible to user)
- Angle: `> 0.005` (0.3° — invisible)
- String/ID: `!=` (any change)

### 5.2 Canvas, Not Shape Views

For high-frequency overlays (60fps), use a single `Canvas` with immediate-mode
drawing. Never compose from SwiftUI `Shape` views — each one is a separate view
identity that SwiftUI diffs every frame.

```swift
Canvas { context, size in
    // All drawing in one closure — one view, one diff
    drawRing(...)
    drawSlice(...)
    drawLabel(...)
}
```

### 5.3 Batch Time Reads

```swift
// BAD — 5 calls to CACurrentMediaTime() per tick
let t1 = CACurrentMediaTime()
...
let t2 = CACurrentMediaTime()

// GOOD — one call, reuse everywhere
let now = CACurrentMediaTime()
```

### 5.4 In-Place Collection Mutation

```swift
// BAD — copies the entire array
ringRevealProgress = Array(ringRevealProgress.prefix(needed))

// GOOD — mutates in-place
if ringRevealProgress.count > needed {
    ringRevealProgress.removeSubrange(needed...)
}
```

---

## 6. Overlay / Floating Window Rendering

### 6.1 NSWindow Configuration for Overlays

```swift
let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
w.isOpaque = false
w.backgroundColor = .clear
w.level = .screenSaver          // above everything
w.ignoresMouseEvents = true     // clicks pass through
w.hasShadow = false
w.collectionBehavior = [.canJoinAllSpaces, .stationary]  // visible on all desktops
```

### 6.2 Positioning at Cursor

```swift
let cursorLoc = NSEvent.mouseLocation      // screen coordinates (bottom-left origin)
let origin = NSPoint(x: cursorLoc.x - size/2, y: cursorLoc.y - size/2)
window.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
window.orderFrontRegardless()
```

### 6.3 Dynamic Window Sizing

Window size is computed from the maximum possible menu depth:
```swift
var overlayWindowSize: Double {
    let maxD = maxMenuDepth()
    let outerR = ringOuterRadius(depth: maxD)
    return (outerR + overlayPadding) * 2
}
```

Ring geometry uses fixed values:
- Dead zone radius: 38pt
- Ring gap: 3pt
- Ring height (configurable): 30–100pt, default 60pt
- Selection width (configurable): 20–80pt, default 45pt
- Overlay padding: 8pt

### 6.4 Glass Slice Drawing Recipe

```swift
// 1. Dark base
context.fill(path, with: .color(Color(white: 0.10, opacity: 0.55)))
// 2. Color tint (brighter when selected)
context.fill(path, with: .color(color.opacity(isSelected ? 0.50 : 0.25)))
// 3. White specular highlight
context.fill(path, with: .color(.white.opacity(isSelected ? 0.10 : 0.04)))
// 4. Border stroke
context.stroke(path, with: .color(.white.opacity(isSelected ? 0.55 : 0.22)), lineWidth: isSelected ? 1.0 : 0.5)
// 5. Selection glow (blur effect on border)
if isSelected {
    var glowCtx = context
    glowCtx.addFilter(.blur(radius: 6))
    glowCtx.stroke(path, with: .color(color.opacity(0.45)), lineWidth: 2.5)
}
```

### 6.5 Curved Text Along Arc

Characters placed individually on the arc. Direction flips based on position
(text reads left-to-right whether at top or bottom of circle):

```swift
let readsCW = sin(midAngle) <= 0  // true when arc is in upper half

for (i, char) in chars.enumerated() {
    if readsCW {
        charAngle = midAngle - totalAngle/2 + t * totalAngle
        rotation = charAngle + .pi/2
    } else {
        charAngle = midAngle + totalAngle/2 - t * totalAngle
        rotation = charAngle - .pi/2
    }
    // translate + rotate context, then draw single character
}
```

Character width approximation: `fontSize * 0.55`.

### 6.6 Rotated SF Symbol Icons — Never Upside-Down

Icons must never appear upside-down regardless of which segment they're in.
Use the same CW/CCW flip logic as `drawCurvedText`: upper half points outward,
lower half points inward. Both branches keep rotation in `[-π/2, π/2]` so
`cos(rotation) > 0` (icon top always faces screen-upward).

```swift
// sin(angle) <= 0  → upper half of circle → icon top points outward
// sin(angle) >  0  → lower half of circle → icon top points inward
let rotation = sin(angle) <= 0 ? angle + .pi / 2 : angle - .pi / 2

var iconCtx = context
iconCtx.translateBy(x: point.x, y: point.y)
iconCtx.rotate(by: .radians(rotation))
iconCtx.draw(Text(Image(systemName: name))
    .font(.system(size: fontSize, weight: .medium))
    .foregroundStyle(.white.opacity(opacity)), at: .zero)
```

**Why the old formula was wrong**: `rotation = angle + π/2` (always outward) makes
icons upside-down for any segment in the right/lower half (angle ∈ (0, π)), because
that puts rotation > π/2, flipping the icon past vertical.

### 6.7 Reveal Animation (Counter-Clockwise Sweep)

Slices reveal in counter-clockwise order from 12 o'clock:
```swift
let sliceCCWStart = sliceAngle * CGFloat(itemCount - 1 - i)  // reversed index
if sliceCCWStart >= revealAngle { continue }                   // not yet revealed
let revealFrac = min((revealAngle - sliceCCWStart) / sliceAngle, 1.0)
let clippedA1 = a2 - revealFrac * (a2 - a1)                   // grow from a2 toward a1
```

Labels fade in at 70% reveal per slice for a staggered, polished look.

### 6.8 Candidate Loading Ring (CandidateOverlay)

Separate NSWindow with CVDisplayLink for smooth 60fps progress arc:
- Yellow arc from 12 o'clock, clockwise
- Starts after a configurable delay (prevents flash on quick taps)
- Uses `CVDisplayLink` (NOT Timer) for frame-perfect animation

---

## 7. Input Capture

### 7.1 MultitouchSupport Private Framework

The key discovery: `NSEvent.touches` doesn't work for global trackpad capture.
We use Apple's private `MultitouchSupport.framework` via `dlopen`:

```swift
dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
```

Functions loaded via `dlsym`:
- `MTDeviceCreateList` → enumerate trackpad devices
- `MTRegisterContactFrameCallback` → register for touch frames
- `MTDeviceStart` / `MTDeviceStop` → lifecycle

**Contact struct layout** (arm64):
- Each contact is 64 bytes
- Normalized (x, y) at byte offset 32 (Float, Float)
- x: 0 (left) to 1 (right), y: 0 (bottom) to 1 (top)

**Callback**: Fires on every touchframe, provides finger count + raw buffer.
Dispatch to main thread for `@Observable` safety.

### 7.2 CGEventTap for Event Suppression

```swift
CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,      // can suppress events
    eventsOfInterest: mask,    // mouse move, clicks, scroll
    callback: handler,
    userInfo: Unmanaged.passUnretained(self).toOpaque()
)
```

During **engaged** state: suppress left/right clicks, scroll wheel (return nil).
During **candidate** state: track cursor movement, cancel if >3pt.
Otherwise: pass through.

**Re-enable on timeout**: The tap can be disabled by the system. Always re-enable:
```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    CGEvent.tapEnable(tap: tap, enable: true)
}
```

### 7.3 Finger Down/Up Detection

MT callback transitions:
- `0 → 1 fingers`: Candidate start (check activation zone margin first)
- `N → 0 fingers`: All fingers up → finalize or cancel
- `1 → 2+ fingers`: Multi-finger gesture → cancel candidate

### 7.4 Activation Zone Margin

Configurable edge exclusion (0–40% from each side):
```swift
let margin = settings.activationMargin / 100.0
if pos.x < margin || pos.x > (1 - margin) { return }  // reject
```

### 7.5 Own-Window Detection

Skip trackpad processing when cursor is over the app's own settings window:
```swift
func isMouseOverOwnWindow() -> Bool {
    for window in NSApp.windows {
        guard window.isVisible, window.isOnActiveSpace,
              window !== candidateOverlay.overlayWindow else { continue }
        if window.frame.contains(NSEvent.mouseLocation) { return true }
    }
    return false
}
```

---

## 8. Action Execution

### 8.1 Keyboard Shortcuts via CGEvent

```swift
let source = CGEventSource(stateID: .hidSystemState)
var flags: CGEventFlags = []
if mapping.useCommand { flags.insert(.maskCommand) }
if mapping.useShift   { flags.insert(.maskShift) }
if mapping.useOption  { flags.insert(.maskAlternate) }
if mapping.useControl { flags.insert(.maskControl) }

let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
down.flags = flags
down.post(tap: .cghidEventTap)
// ... then key up
```

**Do NOT use AppleScript** for keyboard shortcuts — it's slow (~100ms overhead).
CGEvent is instant.

### 8.2 Media Keys via NSEvent

```swift
let data1 = Int((keyType << 16) | Int32(flags))
let event = NSEvent.otherEvent(
    with: .systemDefined, location: .zero,
    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
    timestamp: 0, windowNumber: 0, context: nil,
    subtype: 8, data1: data1, data2: -1
)
event.cgEvent?.post(tap: .cghidEventTap)
```

Key types: `16` = play/pause, `17` = next, `18` = prev, `0` = vol up, `1` = vol down, `7` = mute.

### 8.3 App Launch

Use `open -a` via shell — it handles .app bundles, absolute paths, and app names:
```swift
Process() with ["/bin/zsh", "-c", "open -a 'AppName'"]
```

Quote the app name to handle spaces. Escape single quotes:
```swift
path.replacingOccurrences(of: "'", with: "'\\''")
```

### 8.4 Shell Commands

```swift
Task.detached {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    process.standardOutput = FileHandle.nullDevice
    process.standardError  = FileHandle.nullDevice
    try? process.run()
}
```

---

## 9. Persistence & Settings

### 9.1 Debounced UserDefaults Writes

Sliders fire `didSet` at 60fps during drag. Writing to UserDefaults on every
change is wasteful. Solution: debounce with a 0.3s timer:

```swift
private var saveTimer: Timer?

private func scheduleSave() {
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
        self?.persistAll()
    }
}

private func persistAll() {
    let d = UserDefaults.standard
    d.set(activationHoldDuration, forKey: "activationHoldDuration")
    // ... all properties in one batch
}

var someProperty: Double = 0.6 {
    didSet { scheduleSave() }
}
```

### 9.2 Loading Settings Safely

```swift
if let v = d.object(forKey: "key") as? Type { property = v }
```

Using `object(forKey:) as? Type` instead of `d.double(forKey:)` avoids the
"default is 0" problem — you can tell the difference between "not set" and "set to 0".

### 9.3 Menu Data: JSON in UserDefaults

`RadialMenuStore` encodes/decodes `[RadialCategory]` as JSON:
```swift
if let data = try? JSONEncoder().encode(categories) {
    UserDefaults.standard.set(data, forKey: storageKey)
}
```

This auto-saves on any mutation via `didSet` (no debounce needed — menu edits
are infrequent, unlike slider drags).

---

## 10. Editor UI Patterns

### 10.1 Different Sheets for Different Item Types

```swift
.sheet(item: $editingAction) { binding in
    if binding.wrappedValue.isSubcategory {
        SubcategoryEditorSheet(...)   // Name + Icon only
    } else {
        ActionEditorSheet(...)        // Name + Icon + Type + Shortcut config
    }
}
```

### 10.2 SF Symbol Picker with Groups

Curated groups: Media, Apps, System, Windows, Arrows, Common, Misc.
Each group is an array of symbol names. Layout: group tabs at top, grid of icons below.
Search filters across all groups.

### 10.3 Keyboard Shortcut Recorder

```swift
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    recordedKeyCode = Int(event.keyCode)
    recordedModifiers = event.modifierFlags
    return nil  // swallow the event
}
```

Store the raw `keyCode` (Int) and modifier flags separately. Display the
human-readable key label via `event.charactersIgnoringModifiers`.

### 10.4 Recursive Action List (Unlimited Depth)

```swift
struct ActionListView: View {
    let parentPath: [Int]
    // ... renders actions at this depth
    // For subcategories, recurses with parentPath + [index]
}
```

The same view renders at every depth. Path grows as you go deeper.

---

## 11. Build & Deploy

### 11.1 Project Setup

- **Xcode project**: `radial.xcodeproj`, scheme: `radial`
- **Bundle ID**: `com.jos.radial`
- **Product name**: "Radial"
- **Target**: macOS 26.4+, arm64
- **Build system**: `PBXFileSystemSynchronizedRootGroup` — drop `.swift` files in
  `radial/` folder and they auto-build. No pbxproj edits needed.

### 11.2 App Icon Asset Catalog — Checklist

Xcode **silently skips** icon slots that are missing or have no `filename` key.
The result is an empty `.icns` and no icon in Finder/Dock.

**`Contents.json` must have `"filename"` on every entry:**
```json
{
  "images": [
    { "filename": "icon_16x16.png",      "idiom": "mac", "scale": "1x", "size": "16x16"   },
    { "filename": "icon_16x16@2x.png",   "idiom": "mac", "scale": "2x", "size": "16x16"   },
    { "filename": "icon_32x32.png",      "idiom": "mac", "scale": "1x", "size": "32x32"   },
    { "filename": "icon_32x32@2x.png",   "idiom": "mac", "scale": "2x", "size": "32x32"   },
    { "filename": "icon_128x128.png",    "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "icon_256x256.png",    "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "icon_512x512.png",    "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

**PNG files required** (generate from a 1024×1024 master with LANCZOS resampling):
`16, 32, 64, 128, 256, 512, 1024` px — the **64 px** file is the one most
commonly missed (it covers the 32×32@2x slot).

**After deploy, force Launch Services to register the new icon:**
```bash
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/\
LaunchServices.framework/Versions/A/Support/lsregister -f -R -trusted /Applications/YourApp.app
```
This makes Finder and Dock pick up the icon immediately — no `killall Dock` needed.

### 11.3 Always Build Release

Debug builds use `-Onone` (no optimization), `ENABLE_TESTABILITY=YES`, and no dead
code stripping. Release builds use `-wholemodule` optimization, stripping, and dSYM.

**Binary size**: 2.7 MB (Release) vs 3.8 MB (Debug) — 30% smaller.

```bash
cd /Users/jos/projects/mac/radial

xcodebuild -project radial.xcodeproj \
           -scheme radial \
           -configuration Release \
           -derivedDataPath build-release \
           build 2>&1 | grep -E "error:|BUILD" | head -20
```

### 11.3 Deploy

```bash
pkill -9 "Radial" 2>/dev/null
sleep 0.5
rm -rf "/Applications/Radial.app"
cp -R "build-release/Build/Products/Release/Radial.app" "/Applications/Radial.app"
open -a "/Applications/Radial.app"
```

**NEVER codesign after deploy** — invalidates accessibility permissions.

### 11.4 Debugging a Running App

```bash
# Find PID
ps aux | grep "Radial"

# Sample CPU usage (5 seconds)
sample <PID> 5

# Memory footprint
footprint <PID>

# What to look for in sample output:
# - mach_msg2_trap samples = idle (good, should be >70%)
# - Timer callback samples = our polling overhead (should be <5%)
# - Canvas/draw samples = rendering cost
```

---

## 12. Mistakes Made & How We Fixed Them

### 12.1 `isSubcategory` checking wrong condition
**Bug**: `!(children ?? []).isEmpty` — empty folders treated as actions.
**Fix**: `children != nil` — presence of array means folder, regardless of contents.

### 12.2 Angle wrap-around at 0°/360° boundary
**Bug**: Normalized angles to [-π, π]. When a slice arc spans the 0°/360° boundary,
the angle comparison breaks (e.g., slice from 350° to 10° — is 5° inside?).
**Fix**: Normalize to [0, 2π) using `truncatingRemainder(dividingBy: 2 * .pi)`.
When finger is outside the spread, clamp to nearest edge instead of rejecting.

### 12.3 Deploying Debug builds
**Bug**: Ran `xcodebuild` with `-configuration Debug` for months. `-Onone`,
no dead code stripping, testability overhead.
**Fix**: Switch to `-configuration Release`. 30% smaller binary, whole-module
optimization, measurably better CPU usage.

### 12.4 UserDefaults thrashing on slider drag
**Bug**: Every slider `didSet` wrote to UserDefaults individually, 60 times/sec.
**Fix**: Debounce with 0.3s timer + batch `persistAll()` writing all values at once.

### 12.5 @Observable property writes without delta guards
**Bug**: `fingerRadius = pixelDist` and `fingerAngle = cwAngle` on every tick,
even when values hadn't changed meaningfully. Triggered unnecessary SwiftUI diffs.
**Fix**: Added epsilon checks: `abs(new - old) > threshold` before writing.

### 12.6 Multiple CACurrentMediaTime() calls per tick
**Bug**: Called `CACurrentMediaTime()` 5+ times per tick for different checks.
**Fix**: Single `let now = CACurrentMediaTime()` at tick start, reused everywhere.

### 12.7 Array copy instead of in-place mutation
**Bug**: `Array(prefix(...))` creates a new array every tick.
**Fix**: `removeSubrange(needed...)` mutates in-place.

### 12.8 Fn key detection via NSEvent.flagsChanged
**Bug**: `flagsChanged` is polluted by synthetic events from `CGEvent.post()`.
**Fix**: Use polling with `DispatchSource` at 16ms +
`CGEventSource.flagsState(.hidSystemState)` — but ONLY for polling, never for
event filtering.

### 12.9 Using AppleScript for key simulation
**Bug**: AppleScript via `osascript` for keyboard shortcuts — 100ms+ latency.
**Fix**: CGEvent for keyboard shortcuts (instant). Keep AppleScript only for
things like `open -a`.

### 12.10 macOS key code for "5" is 23, not 22
Key code 22 = "6". This was a silent bug that sent the wrong key. Always verify
key codes against Apple's documented virtual key code table.

## 13. Unfixed / Remaining Issues

These are known but not worth fixing unless they become bottlenecks:

| Issue | Severity | Notes |
|---|---|---|
| `isMouseOverOwnWindow()` loops all windows on every CGEvent | Medium | Could cache window frame |
| `itemsAtDepth()` walks tree every tick | Medium | Could cache per-tick |
| `colorFromHex()` called every frame per ring item | Medium | Could memoize with dictionary |
| `drawCurvedText()` draws character-by-character | Low-Medium | Architectural — hard to optimize |
| CandidateOverlay redundant `needsDisplay` calls | Low | Already fast |

---

## 14. Reusable Components

### 14.1 Direct Reuse (copy the file)

| Component | File | What It Does |
|---|---|---|
| `ActionExecutor` | `ActionExecutor.swift` | Keyboard shortcuts, app launch, shell, media keys |
| `ActionMapping` | `ActionMapping.swift` | Action config model + store |
| Settings UI helpers | bottom of `ContentView.swift` | `SettingsSection`, `SettingsSlider`, `SettingsStepper` |

### 14.2 Patterns to Replicate

| Pattern | Where to Find It | Key Takeaway |
|---|---|---|
| Debounced persistence | `AppSettings.swift` | Timer + batch write |
| Delta-guarded @Observable | `SessionEngine.swift` | Epsilon checks before property writes |
| Glass slice drawing | `SelectionOverlay.swift` | 5-layer compositing recipe |
| Curved text on arc | `SelectionOverlay.swift` | Per-character placement with CW/CCW flip |
| CGEventTap setup | `TrackpadService.swift` | Event suppression + re-enable on timeout |
| MultitouchSupport bridge | `TrackpadService.swift` | dlopen + dlsym + struct memory layout |
| Recursive data CRUD | `RadialMenuModel.swift` | Path-based tree operations |
| NSWindow overlay | `SelectionOverlay.swift` | Borderless, clear, ignoresMouseEvents |
| CVDisplayLink animation | `CandidateOverlay.swift` | Frame-perfect 60fps without Timer coalescing |
| Menu bar status item | `RadialApp.swift` | NSStatusItem + NSMenu |

---

## 15. Quick Reference

### macOS Virtual Key Codes (commonly needed)

```
a=0  s=1  d=2  f=3  h=4  g=5  z=6  x=7  c=8  v=9
b=11 q=12 w=13 e=14 r=15 y=16 t=17
1=18 2=19 3=20 4=21 6=22 5=23 ==24 9=25 7=26 -=27 8=28 0=29
space=49 return=36 tab=48 escape=53 delete=51
up=126 down=125 left=123 right=124
f1=122 f2=120 f3=99 f4=118 f5=96 f6=97 f7=98 f8=100
```

Note: "5" is key code **23** (not 22). "6" is 22. They're not sequential.

### Media Key Types (NX_KEYTYPE constants)

```
Play/Pause = 16    Next Track = 17    Previous Track = 18
Volume Up  = 0     Volume Down = 1    Mute = 7
```

### Ring Geometry Constants

```
deadZoneRadius = 38pt
ringGap = 3pt
overlayPadding = 8pt
ringHeight = 60pt (configurable 30–100)
selectionWidth = 45pt (configurable 20–80)
```

### Color Hex → SwiftUI Color

```swift
func colorFromHex(_ hex: String) -> Color {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard h.count == 6, let val = UInt64(h, radix: 16) else { return .blue }
    return Color(red: Double((val >> 16) & 0xFF) / 255,
                 green: Double((val >> 8) & 0xFF) / 255,
                 blue: Double(val & 0xFF) / 255)
}
```
