# Radial Agent Instructions

Before building, installing, launching, debugging Spaces, or claiming a fix is
ready to test, read and follow `DEPLOYMENT_RUNBOOK.md` completely.

Project-specific requirements:

- "Fix it so I can test" includes Release build, correct existing-team signing,
  recoverable installation to `/Applications/Radial.app`, launch, and UI-level
  verification unless the user explicitly limits the scope.
- Never substitute ad-hoc signing for Radial's established signing identity and
  never re-sign the installed bundle.
- A successful build or PID is not proof of deployment. Verify hashes/signature,
  the menu-bar item, visible overlay pixels after the affected interaction,
  delayed liveness, and absence of a new crash report.
- For Spaces bugs, trace configuration, raw input, engagement, WindowServer
  state, and actual pixels separately. Do not rebuild healthy listeners based on
  timing correlation alone.
- Preserve the user's preferences, Accessibility identity, backups, and unrelated
  working-tree changes.
