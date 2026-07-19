# Radial — Lessons Learned

Short, practical notes. Only confirmed, tested things.

---

## Tuning Values That Worked

| Setting | Value | Notes |
|---|---|---|
| Activation hold duration | 0.6 s | Feels intentional but not slow |
| Candidate ring delay | 0.25 s | Prevents flash on quick taps |
| Finger-move cancel threshold | 3 pt | Lets users still use trackpad normally |
| Delta guard — position/radius | > 0.5 pt | Invisible to user, cuts SwiftUI diffs |
| Delta guard — angle | > 0.005 rad (≈0.3°) | Same — eliminates jitter redraws |
| UserDefaults debounce | 0.3 s | Covers fastest slider drags without lag |
| Dead zone radius | 38 pt | Big enough to hit, small enough not to waste ring space |
| Ring gap | 3 pt | Visual separation without eating real estate |
| Ring height | 60 pt (range 30–100) | 60 is the sweet spot for readability |
| Selection width | 45 pt (range 20–80) | Matches average finger tip travel |
| Overlay padding | 8 pt | Just enough to keep ring from clipping window edge |
| Timer interval (polling loop) | 16 ms (1/60 s) | Matches display refresh; faster gave no benefit |
| MT contact struct — xy offset | byte 32 (Float, Float) | Confirmed for arm64 |

---

## Things That Caused Problems

**`isSubcategory` checking `children.isEmpty` instead of `children != nil`**
Empty folders were treated as actions. Fix: `children != nil` always means folder.

**Angle normalization to [-π, π] instead of [0, 2π)**
Slices spanning the 0°/360° boundary broke. Fix: `truncatingRemainder(dividingBy: 2 * .pi)` with clamping when outside spread.

**Building with Debug configuration**
`-Onone`, testability overhead, 30% larger binary. Always use Release for any real test.

**Writing to UserDefaults on every slider `didSet`**
60 writes/sec per slider. Fix: debounce with 0.3 s timer, write all values in one `persistAll()`.

**`@Observable` writes without delta guards**
Triggered full SwiftUI diffs on every 60fps tick even when nothing changed. Fix: epsilon check before every property write inside the polling loop.

**Multiple `CACurrentMediaTime()` calls per tick**
Called 5+ times per tick. Fix: one `let now = CACurrentMediaTime()` at tick start, reused everywhere.

**`Array(prefix(...))` instead of `removeSubrange`**
Copies entire array every tick. Fix: mutate in-place.

**Codesigning after deploying to `/Applications/`**
Invalidates accessibility permissions — macOS sees it as a new app identity. Never re-codesign a deployed binary.

**Changing the bundle ID after release**
Breaks previously granted accessibility permissions. Treat `com.jos.radial` as stable once shipped.

**AppleScript for keyboard shortcuts**
~100 ms latency. Fix: CGEvent for all keyboard posting (instant).

**Key code 22 vs 23**
"5" = 23, "6" = 22. They're not sequential — always check against Apple's key code table.

**`NSEvent.touches` for global trackpad capture**
Doesn't work globally. Must use `MultitouchSupport.framework` via dlopen.

---

## Build / Run Steps That Work

**Build Release:**
```bash
cd /Users/jos/projects/mac/radial

xcodebuild -project radial.xcodeproj \
           -scheme radial \
           -configuration Release \
           -derivedDataPath build-release \
           build 2>&1 | grep -E "error:|BUILD" | head -20
```

**Deploy:**
```bash
pkill -9 "Radial" 2>/dev/null
sleep 0.5
rm -rf "/Applications/Radial.app"
cp -R "build-release/Build/Products/Release/Radial.app" "/Applications/Radial.app"
open -a "/Applications/Radial.app"
```

**Check CPU usage (5-second sample):**
```bash
ps aux | grep "Radial"   # get PID
sample <PID> 5
```
Good: `mach_msg2_trap` samples > 70% (idle). Bad: Timer callback or Canvas > 5%.

**Add a new Swift file:**
Drop `.swift` into `radial/` folder — it auto-builds via `PBXFileSystemSynchronizedRootGroup`. No pbxproj edits needed.

---

## Useful Log Messages and What They Mean

All logs prefix with `[TrackpadService]`.

| Message | Meaning |
|---|---|
| `Started — MT devices: N, event tap: ok` | Normal startup. N should be ≥ 1. If N=0, no trackpad found. |
| `Failed to create event tap — grant Accessibility permission.` | App not in Accessibility list. Open System Settings → Privacy → Accessibility and add it. |
| `MultitouchSupport framework not available` | `dlopen` failed. Framework path wrong or OS restriction. |
| `Registered N multitouch device(s)` | MT devices bound. N=0 means trackpad not detected at that point. |
| `MT: finger down (0→1), starting hold timer` | Candidate state entered. Hold timer counting toward activation. |
| `MT: all fingers up (N→0), engaged=true/false` | Fingers lifted. `engaged=true` means action will fire; `false` = cancelled. |
| `MT: multi-finger (N→M), cancelling` | Two or more fingers detected — gesture cancelled to avoid conflict with system gestures. |
| `ENGAGED — cursor free, clicks suppressed` | Overlay is live. Mouse clicks are being intercepted. |
| `DISENGAGED` | Overlay dismissed. Normal input restored. |
