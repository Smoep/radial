# Radial

**A macOS radial action launcher driven entirely by your trackpad.**

## Download

[**→ Download Radial.zip from the latest release**](https://github.com/Smoep/radial/releases/latest)

Unzip and drag **Radial.app** to your Applications folder.

> **First launch:** macOS will show a security warning because the app is not signed with an Apple Developer certificate.
> Right-click (or Control-click) the app → **Open** → **Open**. You only need to do this once.

Touch and hold the trackpad, slide your finger to the action you want, then lift. No mouse movement, no keyboard hunting — just one fluid gesture.

![Radial Menu Concept](Radial%20Menu%20Concept%20Dma.jpg)

---

## How it works

1. **Touch & hold** anywhere on the trackpad — a progress ring fills over ~0.6 s.
2. **The pie menu appears** at your cursor, organized in concentric rings.
3. **Slide outward** to a category slice, then further out to an action.
4. **Lift your finger** — the action fires instantly.

The center of the menu is always a cancel zone. Your finger never leaves the trackpad.

---

## What you can trigger

- **Keyboard shortcuts** — any key combo (recorded live from your keyboard)
- **Launch apps** — open any application instantly
- **Shell commands** — run arbitrary scripts
- **Media controls** — play/pause, next/previous track, volume, mute

---

## Features

- Unlimited nesting — categories can contain subcategories at any depth
- Fully customizable menu via a built-in drag-and-drop editor
- Two selection modes: **lift-to-select** (fast) or **click-to-confirm** (forgiving)
- Lives in the menu bar — no Dock icon, zero visual clutter
- Glass-style overlay aesthetic native to macOS 26
- Per-app awareness — pause tracking when you don't need it

---

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ to build from source

---

## Build & install

```bash
git clone https://github.com/Smoep/radial.git
cd radial
xcodebuild -project radial.xcodeproj -scheme radial -configuration Release \
  -derivedDataPath build-release build
cp -R build-release/Build/Products/Release/Radial.app /Applications/Radial.app
open /Applications/Radial.app
```

---

## License

GPL-3.0 — see [LICENSE](LICENSE).
