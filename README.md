# Radial

**Execute any action in one gesture — touch, slide, lift.**

Radial is a macOS launcher that lives in your trackpad. Touch and hold anywhere, a circular menu appears at your cursor, slide your finger to what you want, and lift. No mouse movement, no reaching for a keyboard shortcut, no hunting through menus — just one continuous motion.

## Download

[**→ Download Radial.zip from the latest release**](https://github.com/Smoep/radial/releases/latest)

Unzip and drag **Radial.app** to your Applications folder.

> **First launch:** macOS may show a security warning because this download is not notarized for public distribution.
> Right-click (or Control-click) the app → **Open** → **Open**. You only need to do this once.

![Radial Menu Concept](Radial%20Menu%20Concept%20Dma.jpg)

---

## How it works

1. **Touch & hold** — rest your finger on the trackpad for about half a second. A progress ring shows you it's counting.
2. **The menu appears** — a circular overlay opens right at your cursor, arranged in rings. Categories in the inner ring, actions in the outer ring.
3. **Slide to your action** — no clicking, just move your finger. The slice you're on highlights instantly.
4. **Lift to confirm** — the action fires the moment your finger leaves the trackpad.

The center is always a cancel zone. If you change your mind, slide back to the middle and lift.

---

## What you can do

- **Run a keyboard shortcut** — trigger any key combination in the app that's currently in focus
- **Launch an app** — open any application in one gesture
- **Open a folder** — jump straight to a location in Finder
- **Open a file** — open any document in its default app
- **Open a URL** — a webpage, a mail link, or anything with a URL scheme
- **Control media** — play/pause, skip tracks, adjust volume
- **Run a shell command** — execute any script or terminal command in the background
- **Trigger a Shortcut** — run any workflow from the macOS Shortcuts app

---

## What makes it flexible

- **Different menus per app** — set up a separate menu for each application. Switching to Chrome, VS Code, or Figma automatically loads the right menu. Press Space while the overlay is open to toggle between the app menu and your global one.
- **Unlimited depth** — categories can contain subcategories, which can contain subcategories. Build as deep a hierarchy as you need.
- **Drag-and-drop editor** — reorder, nest, and color-code everything from the settings window. No config files.
- **Smart labels** — long names wrap onto two lines automatically. Use ⌥Return in the name field to set the break point yourself. CJK and emoji are supported.
- **Two ways to select** — lift your finger to confirm (fast), or keep the overlay open and click (more forgiving for new users).
- **Backup & restore** — export your entire setup as a file and import it on another machine.
- **Quiet by default** — no Dock icon, no windows until you open settings from the menu bar.

---

## Requirements

- macOS 26 (Tahoe) or later

---

## Build from source

Maintainers and coding agents should follow [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md)
for signed local deployment, rollback, and UI-level verification. A successful
build alone is not considered a deployed test version.

```bash
git clone https://github.com/Smoep/radial.git
cd radial
xcodebuild -project radial.xcodeproj -scheme radial -configuration Release \
  -derivedDataPath build-release build
cp -R build-release/Build/Products/Release/Radial.app /Applications/Radial.app
open -a /Applications/Radial.app
```

---

## License

GPL-3.0 — see [LICENSE](LICENSE).
