# Radial

**Execute any Mac action in one fluid gesture.**

Radial is a menu-bar launcher for macOS. Open a circular menu at the pointer,
move through categories and actions, then lift or click to run the selection.
Build one global menu or give individual apps their own context-specific menus.

## Download Radial 1.5.9

[**Download Radial.zip from the latest release**](https://github.com/Smoep/radial/releases/latest)

New to Radial? Follow the [illustrated setup and settings guide](https://smoep.github.io/radial/).

Requires **macOS 26.4 or later**. Unzip the download and move **Radial.app** to
Applications.

> **First launch:** Radial is signed but not notarized. Right-click (or
> Control-click) **Radial.app**, choose **Open**, then confirm **Open**. macOS will
> also ask for Accessibility access so Radial can observe the configured trigger
> and execute shortcuts.

![A colorful Radial menu with nested actions](Radial%20Menu%20Concept%20Dma.jpg)

## Start from an empty menu

A new installation intentionally contains no sample actions. To make your first
working menu:

1. Open Radial from the menu-bar icon and choose **Settings**.
2. In **Menu → Global Menu**, click **Add Category**.
3. Name it, choose an SF Symbol or emoji and a colour, then click **Save**.
4. Expand the category and click **Add Action**.
5. Name the action, choose its type and fill in the type-specific value.
6. Click **Save**, open the menu with your configured trigger and select it.

The [complete guide](https://smoep.github.io/radial/#first-menu) explains every
action type, trigger and appearance control, including numbered slices, ring
height, slice width, nested categories and app-specific menus.

## Features

- Keyboard, trackpad and mouse triggers, each independently configurable
- Keyboard shortcuts, applications, folders, files, URLs, Apple Shortcuts,
  shell commands, media controls and multi-step automations
- Unlimited nested categories with drag-and-drop organization
- A global menu plus optional menus for specific applications
- Numbered slices for keyboard navigation (`1`–`9`, and `0` for slice 10)
- Adjustable ring height, slice width, label size, wrapping and overlay opacity
- Lift-to-select or click-to-confirm interaction styles
- Start at Login using the native macOS login-item service
- Backup and restore for menus and settings
- Test Mode for safely checking a menu without running its actions

The center of the overlay is always a safe place to return or cancel. Radial
runs quietly without a Dock icon and keeps menu data locally in macOS preferences.

## Project documentation

- [User guide](https://smoep.github.io/radial/)
- [Release history](CHANGELOG.md)
- [Deployment runbook](DEPLOYMENT_RUNBOOK.md)
- [Engineering handoff](HANDOFF.md)
- [Lessons learned](LESSONS_LEARNED.md)

## Build from source

Maintainers and coding agents must follow [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md)
for signed local deployment, rollback and UI-level verification. A successful
build alone is not considered a deployed test version.

```bash
git clone https://github.com/Smoep/radial.git
cd radial
xcodebuild -project radial.xcodeproj -scheme radial -configuration Release \
  -derivedDataPath build-release build
```

The established project signing identity is required for a locally deployable
build. Do not re-sign the finished app ad hoc.

## License

GPL-3.0 — see [LICENSE](LICENSE).
