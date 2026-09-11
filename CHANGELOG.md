# Release history

## 1.5.10 — 2026-09-11

- Fixed clicks on a visible Radial menu being ignored when the separate mouse
  trigger was disabled.
- Rebuilds the input event tap after wake or session activation and periodically
  repairs stale input listeners.
- Restored active-Space recovery so stale overlay panels are retired cleanly.
- Added a click-confirmation fallback for cases where macOS stops delivering
  clicks through the consuming event tap.

## 1.5.9 — 2026-09-09

- Added **Start Radial at Login** in Settings → Behavior.
- Fresh installations now start with an empty menu instead of bundled sample
  categories and actions. Existing menus are preserved.
- Removed the obsolete **Ring Delay** control and stale persisted appearance
  values that no longer had a user-facing effect.
- Audited the remaining settings against their runtime behavior.
- Added a complete first-run, action, settings and advanced-use guide with real
  app screenshots and numbered visual callouts.

## 1.5.8

- Previous tagged release.
