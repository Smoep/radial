# Radial Build, Deploy, and Verification Runbook

This is the required workflow whenever a change is meant to be tested in the
installed app. A source fix is not delivered until the installed, signed app has
been replaced, launched, and verified at the UI level.

## Definition of Done

When the user asks to fix and deploy Radial, completion means all of the following:

1. Implement the scoped source change without overwriting unrelated work.
2. Run relevant tests and `git diff --check`.
3. Build a Release app signed with Radial's existing Apple Development identity.
4. Verify the build's bundle ID, team ID, and designated requirement.
5. Preserve the currently installed app as a recoverable backup.
6. Install the new app at `/Applications/Radial.app`.
7. Launch it.
8. Verify the installed binary hash matches the built binary.
9. Verify the process remains alive and no new crash report appears.
10. Verify the real UI: the menu-bar item exists and the radial overlay visibly
    renders after the exact interaction affected by the change.

Do not say "deployed", "running", or "fixed" before the matching verification
has completed. Clearly distinguish "build succeeded" from "installed and tested".

## Signing Rules

Radial's stable identity is:

- Bundle ID: `com.jos.radial`
- Team ID: `A6CM288C33`
- Current development certificate: `Apple Development: i3mi@mailbox.org (VF95NL2PBD)`

Before replacing the app, compare the new build with the currently installed app:

```bash
codesign -d --verbose=4 /Applications/Radial.app 2>&1
codesign -d -r- /Applications/Radial.app 2>&1
security find-identity -v -p codesigning
```

Build with the matching identity. The certificate SHA-1 may change when
certificates are renewed, so discover it rather than copying an old hash blindly:

```bash
xcodebuild -project radial.xcodeproj -scheme radial -configuration Release \
  -derivedDataPath /private/tmp/radial-release \
  DEVELOPMENT_TEAM=A6CM288C33 \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='<matching certificate SHA-1>' \
  build
```

Important:

- Never replace a team-signed installation with an ad-hoc-signed build merely to
  get past an Xcode signing error.
- Never re-sign the bundle after copying it to `/Applications`.
- Keep the bundle ID, team ID, and designated requirement stable so macOS
  Accessibility trust continues to recognize Radial.
- If the correct identity is unavailable, stop and report that specific blocker.

## Tests

Run unit tests without signing:

```bash
xcodebuild test -project radial.xcodeproj -scheme radial \
  -configuration Debug \
  -derivedDataPath /private/tmp/radial-tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:radialTests
```

If the sandbox blocks Xcode's Swift macro plugins, rerun the same command with
normal host access. Do not misreport an environment/plugin failure as a source
test failure.

Unit tests do not validate Mission Control, Spaces, WindowServer membership,
Accessibility, global input monitors, or visible overlay rendering. Those require
an installed-app regression test.

## Recoverable Installation

Use a unique backup path and verify it does not already exist. Avoid deleting the
installed app when it can be moved aside for rollback.

```bash
killall Radial 2>/dev/null || true
test ! -e /private/tmp/Radial.app.before-next-deploy
mv /Applications/Radial.app /private/tmp/Radial.app.before-next-deploy
ditto /private/tmp/radial-release/Build/Products/Release/Radial.app \
  /Applications/Radial.app
open -a /Applications/Radial.app
```

Then verify identity and binary equality:

```bash
shasum -a 256 \
  /private/tmp/radial-release/Build/Products/Release/Radial.app/Contents/MacOS/Radial \
  /Applications/Radial.app/Contents/MacOS/Radial
codesign -d --verbose=2 /Applications/Radial.app 2>&1
codesign -d -r- /Applications/Radial.app 2>&1
pgrep -afil '/Applications/Radial.app/Contents/MacOS/Radial'
```

## UI and Stability Verification

A PID is only evidence that the app existed at that instant. It is not proof that
the menu-bar app is usable or that it stayed alive.

Verify all relevant layers:

- Confirm the Radial `hand.draw.fill` status item exists and its menu opens.
- Confirm the menu contains `Pause Tracking`, `Settings…`, and `Quit Radial`.
- Trigger the overlay and capture/inspect the screen. A WindowServer entry with
  `kCGWindowIsOnscreen = 1` can still contain fully transparent content.
- Wait through delayed cleanup/timers, then check the PID again.
- Check `~/Library/Logs/DiagnosticReports/Radial*.ips` for a newer crash.
- Inspect unified logs with:

```bash
/usr/bin/log show --info --last 10m \
  --predicate 'process == "Radial" AND subsystem == "com.jos.radial"' \
  --style compact
```

When testing an input problem, first read the saved configuration. Do not silently
change the user's preferred triggers:

```bash
defaults read com.jos.radial trackpadEnabled
defaults read com.jos.radial mouseEnabled
defaults read com.jos.radial hotkeyEnabled
defaults read com.jos.radial hotkeyMode
```

## Spaces Regression Test

For any overlay, listener, window, or Mission Control change, test the actual bug:

1. Confirm Radial renders on Desktop 1.
2. Switch through existing Desktops and render once on each.
3. Create two additional Desktops.
4. Render once on each new Desktop.
5. Delete one or two Desktops.
6. Switch through every remaining Desktop and render once on each.
7. Test the trigger modes that are enabled in the user's settings.
8. Visually verify the overlay rather than relying only on `ENGAGED` logs.
9. Confirm Radial stays alive and produces no new crash report.

If automation cannot create/delete Spaces reliably, the user performs those UI
steps while diagnostic logging remains enabled; inspect the exact failed
transition immediately afterward.

## Confirmed Lessons from the Spaces Bug

The August 2026 investigation established these facts:

- Global multitouch input continued after Space changes. Logs showed MT frames and
  `ENGAGED — overlay opening` on the failed Desktop.
- WindowServer could report the cached selection panel as onscreen, correctly
  sized, and centered under the cursor while its SwiftUI contents were completely
  transparent. A screenshot was necessary to prove this.
- The failure was stale overlay-panel/Space backing, not a corrupted mouse-event
  listener.
- `MTDeviceStop`/`MTDeviceStart` during a Space change is unsafe. It can leave
  WindowServer receiving trackpad frames while Radial's private-framework callback
  silently stops. Multitouch registration is hardware-global and should live for
  the service lifetime.
- Closing/releasing the AppKit/SwiftUI panel directly inside
  `activeSpaceDidChangeNotification` is unsafe and caused an `EXC_BAD_ACCESS` in
  `objc_release`.
- The implemented strategy retires the stale `SelectionOverlay` panel, lets the
  next `show` create a fresh panel on the active Space, and releases retired panels
  after WindowServer has settled.
- Do not rebuild healthy input systems merely because the symptom occurs after a
  Space switch. Trace input reception, engagement, WindowServer state, and actual
  pixels separately.

## Debugging Order

Use this order to avoid guessing:

1. **Configuration:** Is the trigger enabled? Is typing suppression active?
2. **Raw input:** Are MT/NSEvent/CGEvent callbacks arriving?
3. **Gesture state:** Was the candidate cancelled by movement, multiple fingers,
   scrolling, early lift, or typing?
4. **Engagement:** Did Radial log `ENGAGED — overlay opening`?
5. **Window state:** Does WindowServer list the panel, with the expected bounds?
6. **Pixels:** Is the overlay actually visible in a screenshot?
7. **Lifetime:** Did the process remain alive, and is there a new `.ips` report?

Only modify the first layer proven to be failing.

## Communication Rules

- Treat "fix it so I can test" as authorization to build, sign, install, launch,
  and verify the local app unless the user explicitly limits the request.
- Do not make the user repeatedly ask for deployment after implementation.
- State blockers precisely and only when they are real.
- Do not ask for signing help before checking the installed signature and local
  Keychain identities.
- Preserve user settings and unrelated working-tree changes.
- If a deployment fails, say what is currently installed and whether rollback is
  available.
