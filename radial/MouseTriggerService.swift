import AppKit
import CoreGraphics
import os

private let mouseLog = Logger(subsystem: "com.jos.pinch-control-3d", category: "mouse")

/// Standalone mouse-button trigger for the radial overlay.
///
/// Modeled on the trackpad trigger (activation button + hold duration + confirm
/// mode) but fully isolated: it owns its own global NSEvent monitors, its own
/// loading-ring overlay, and its own hold timer. It never touches TrackpadService
/// internals — all shared engagement actions go through injected closures, so the
/// trackpad and keyboard paths cannot regress.
///
/// No Accessibility permission required — NSEvent global monitors for mouse events
/// work without any permission on macOS 12+.
final class MouseTriggerService {

    // MARK: - Injected dependencies

    var settings: AppSettings?
    /// Whether the overlay is currently showing.
    var isEngaged: (() -> Bool)?
    /// Whether a finger is physically on the trackpad (distinguishes a real mouse
    /// left-click from a trackpad tap/click when the trigger button is Left).
    var hasTrackpadContact: (() -> Bool)?
    /// Guard checked before activating (e.g. typing suppression). Returns false to block.
    var canActivate: (() -> Bool)?
    /// Open the overlay at the current cursor position.
    var onOpen: (() -> Void)?
    /// Dismiss the overlay without selecting.
    var onDismiss: (() -> Void)?
    /// Confirm the currently-hovered selection.
    var onSelect: (() -> Void)?

    // MARK: - Internal state

    private var eventMonitors: [Any] = []
    private let loadingRing = CandidateOverlay()

    /// Button that started the current activation (nil = idle).
    private var armedButton: Int? = nil
    /// True while the hold timer is running (candidate phase, before engage).
    private var candidateInProgress = false
    private var holdTimerID: UInt = 0
    private var candidateMoveDistance: CGFloat = 0
    private var lastCandidateScreen: CGPoint = .zero

    // MARK: - Lifecycle

    func start() {
        guard eventMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved
        ]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            eventMonitors.append(m)
        }
        mouseLog.info("MouseTriggerService started")
    }

    func stop() {
        for m in eventMonitors { NSEvent.removeMonitor(m) }
        eventMonitors.removeAll()
        loadingRing.hide()
        resetCandidate()
    }

    deinit { stop() }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:   handleDown(button: 0)
        case .leftMouseUp:     handleUp(button: 0)
        case .otherMouseDown:  handleDown(button: event.buttonNumber)
        case .otherMouseUp:    handleUp(button: event.buttonNumber)
        case .mouseMoved, .leftMouseDragged, .otherMouseDragged:
            handleMove(event)
        default: break
        }
    }

    private var triggerButton: Int { settings?.mouseButton.buttonNumber ?? 2 }

    private func handleDown(button: Int) {
        guard settings?.mouseEnabled == true else { return }

        // ── Already engaged: confirm or dismiss ──
        if isEngaged?() == true {
            let releaseMode = settings?.mouseReleaseToSelect ?? true
            if !releaseMode, button == 0 {
                // Click-to-select: a left click confirms the hovered item.
                onSelect?()
            } else if button == triggerButton {
                // Pressing the trigger button again dismisses.
                onDismiss?()
                resetCandidate()
            }
            return
        }

        // ── Not engaged: only the trigger button starts activation ──
        guard button == triggerButton else { return }

        // Left button: ensure it's a real mouse click, not a trackpad tap/click.
        if triggerButton == MouseButton.left.buttonNumber, hasTrackpadContact?() == true { return }

        // Typing suppression / other guards.
        if canActivate?() == false { return }
        if isMouseOverOwnWindow() { return }

        let hold = settings?.mouseHoldDuration ?? 0
        armedButton = button

        if hold <= 0.001 {
            // Immediate engage.
            mouseLog.info("mouse down (button \(button, privacy: .public)) → immediate open")
            onOpen?()
        } else {
            // Press-and-hold: show loading ring, engage when the timer fires.
            candidateInProgress = true
            candidateMoveDistance = 0
            let nsLoc = NSEvent.mouseLocation
            if let screen = NSScreen.main {
                lastCandidateScreen = CGPoint(x: nsLoc.x, y: screen.frame.height - nsLoc.y)
            }
            loadingRing.show(at: nsLoc, duration: hold, delay: settings?.ringDelay ?? 0.25)
            startHoldTimer(hold)
            mouseLog.info("mouse down (button \(button, privacy: .public)) → hold \(hold, privacy: .public)s")
        }
    }

    private func handleUp(button: Int) {
        guard settings?.mouseEnabled == true else { return }
        guard button == armedButton else { return }

        // Released before the hold threshold → cancel.
        if candidateInProgress {
            resetCandidate()
            return
        }

        // Released while engaged → confirm if in release-to-select mode.
        if isEngaged?() == true, settings?.mouseReleaseToSelect ?? true {
            onSelect?()
        }
        armedButton = nil
    }

    private func handleMove(_ event: NSEvent) {
        guard candidateInProgress else { return }
        let screenLoc = CGPoint(x: event.cgEvent?.location.x ?? 0,
                                y: event.cgEvent?.location.y ?? 0)
        candidateMoveDistance += abs(screenLoc.x - lastCandidateScreen.x)
                              +  abs(screenLoc.y - lastCandidateScreen.y)
        lastCandidateScreen = screenLoc
        if candidateMoveDistance > 3 { resetCandidate() }
    }

    // MARK: - Hold timer

    private func startHoldTimer(_ hold: Double) {
        holdTimerID &+= 1
        let capturedID = holdTimerID
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.holdTimerID == capturedID, self.candidateInProgress else { return }
            if self.canActivate?() == false { self.resetCandidate(); return }
            self.candidateInProgress = false
            self.loadingRing.hide()
            self.onOpen?()
        }
    }

    private func resetCandidate() {
        holdTimerID &+= 1
        candidateInProgress = false
        candidateMoveDistance = 0
        armedButton = nil
        loadingRing.hide()
    }

    // MARK: - Helpers

    private func isMouseOverOwnWindow() -> Bool {
        let mouseLoc = NSEvent.mouseLocation
        for window in NSApp.windows {
            guard window.isVisible, window.isOnActiveSpace,
                  window !== loadingRing.overlayWindow else { continue }
            if window.frame.contains(mouseLoc) { return true }
        }
        return false
    }
}
