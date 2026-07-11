import Foundation
import AppKit
import CoreGraphics
import Darwin
import os

private let tzLog = Logger(subsystem: "com.jos.pinch-control-3d", category: "trackpad")

// MARK: - MultitouchSupport private framework bridge

private typealias MTDeviceRef = OpaquePointer
private typealias MTContactCallback = @convention(c) (
    MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32
) -> Void

/// Simplified layout of an MTContact struct (only fields we need).
/// The normalized position (x, y) is at byte offset 24 in the struct (after 12 bytes of header + 12 bytes).
/// Each contact is 64 bytes on arm64.
private struct MTContactPoint {
    var x: Float  // normalised 0–1, left to right
    var y: Float  // normalised 0–1, bottom to top
}

private let contactStride = 64  // bytes per contact on arm64
private let positionOffset = 32 // byte offset to normalized (x, y) pair
/// Minimum instantaneous MT contact size for a leftMouseDown to count as a real
/// physical click (finger pressed on pad) rather than a tap-to-click tap (~0).
private let clickFingerPresenceThreshold: Float = 0.3

private let mtLib: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
}()

private let _MTDeviceCreateList: (@convention(c) () -> Unmanaged<CFArray>)? = {
    guard let lib = mtLib, let sym = dlsym(lib, "MTDeviceCreateList") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) () -> Unmanaged<CFArray>).self)
}()

private let _MTRegisterContactFrameCallback: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void)? = {
    guard let lib = mtLib, let sym = dlsym(lib, "MTRegisterContactFrameCallback") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
}()

private let _MTDeviceStart: (@convention(c) (MTDeviceRef, Int32) -> Void)? = {
    guard let lib = mtLib, let sym = dlsym(lib, "MTDeviceStart") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
}()

private let _MTDeviceStop: (@convention(c) (MTDeviceRef) -> Void)? = {
    guard let lib = mtLib, let sym = dlsym(lib, "MTDeviceStop") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef) -> Void).self)
}()

// Global weak ref — MTRegisterContactFrameCallback has no refcon parameter.
private weak var _sharedTrackpadService: TrackpadService?

// Multitouch frame callback — fires on every touch frame from any MT device.
private func mtFrameCallback(
    _ device: MTDeviceRef,
    _ data: UnsafeMutableRawPointer,
    _ nFingers: Int32,
    _ timestamp: Double,
    _ frame: Int32
) {
    // Extract first finger position if available.
    var pos: CGPoint? = nil
    var fSize: Float = 0
    var fDensity: Float = 0
    if nFingers >= 1 {
        let ptr = data.advanced(by: positionOffset)
        let x = ptr.load(as: Float.self)
        let y = ptr.advanced(by: 4).load(as: Float.self)
        pos = CGPoint(x: CGFloat(x), y: CGFloat(y))
        // MTTouch: size (zTotal) at offset 48, density (zDensity) at offset 92.
        fSize = data.advanced(by: 48).load(as: Float.self)
        fDensity = data.advanced(by: 92).load(as: Float.self)
    }

    // Dispatch to main for @Observable safety.
    DispatchQueue.main.async {
        _sharedTrackpadService?.handleMultitouch(fingerCount: nFingers, touchPosition: pos, size: fSize, density: fDensity)
    }
}

// MARK: - TrackpadService

/// One-finger touch+hold trackpad activation using MultitouchSupport + NSEvent global monitors.
///
/// No Accessibility permission required: MultitouchSupport is a private framework
/// (dlopen, no permission needed) and NSEvent global monitors for mouse events
/// work without any permission on macOS 12+.
@Observable
final class TrackpadService {

    // MARK: - State exposed to SessionEngine

    private(set) var isTouching: Bool = false
    private(set) var touchPosition: CGPoint = .zero
    private(set) var touchPhase: TouchPhase = .idle
    private(set) var scaledPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var isEngaged: Bool = false
    /// Set to true when a click occurs during engaged state. Consumed by SessionEngine.
    private(set) var pendingClick: Bool = false

    var settings: AppSettings?

    /// Closure checked before engaging — if it returns true, candidate is cancelled instead.
    var shouldSuppressActivation: (() -> Bool)?

    enum TouchPhase { case idle, began, moved, ended, cancelled }

    // MARK: - Phase queue

    private var phaseQueue: [TouchPhase] = []

    func consumePhases() -> [TouchPhase] {
        let q = phaseQueue
        phaseQueue.removeAll()
        return q
    }

    /// Consume the pending click flag. Returns true if a click occurred.
    func consumeClick() -> Bool {
        if pendingClick {
            pendingClick = false
            return true
        }
        return false
    }

    // MARK: - Internal state

    private var eventMonitors: [Any] = []
    private var runLoopSource: CFRunLoopSource? = nil  // unused; kept for rollback reference
    private var mtDevices: [MTDeviceRef] = []
    private let candidateOverlay = CandidateOverlay()

    /// Whether a single finger is resting on the trackpad (candidate or engaged).
    private var fingerDown: Bool = false
    /// Previous finger count from multitouch callback.
    private var prevFingerCount: Int32 = 0
    /// Set true on engage(); cleared on first finger-lift. Prevents initial lift from triggering a click.
    private var justEngaged: Bool = false
    /// DIAG: latest and peak per-finger contact size/density from the MT frame.
    private var lastFingerSize: Float = 0
    private var lastFingerDensity: Float = 0
    private var peakFingerSize: Float = 0
    private var peakFingerDensity: Float = 0
    /// Candidate hold timer ID — cancelled on movement or finger lift.
    private var holdTimerID: UInt = 0
    /// Cumulative cursor movement during candidate phase.
    private var candidateMoveDistance: CGFloat = 0
    /// Last screen position for computing deltas during candidate.
    private var lastCandidateScreen: CGPoint = .zero
    /// Cursor position when finger touched down while engaged (for tap detection).
    private var engagedTouchStart: CGPoint = .zero

    // MARK: - Lifecycle

    func start() {
        guard eventMonitors.isEmpty else { return }
        _sharedTrackpadService = self

        // ── Start MultitouchSupport (no permission needed) ──
        startMultitouch()

        // ── Global event monitors for mouse events (no Accessibility needed) ──
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .scrollWheel, .mouseMoved
        ]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleGlobalEvent(event)
        }) {
            eventMonitors.append(m)
        }
        tzLog.info("Started — MT devices: \(self.mtDevices.count), global monitors: ok")
    }

    private func startMultitouch() {
        guard let createList = _MTDeviceCreateList,
              let register = _MTRegisterContactFrameCallback,
              let startDev = _MTDeviceStart else {
            print("[TrackpadService] MultitouchSupport framework not available")
            return
        }

        let cfDevices = createList().takeRetainedValue()
        let count = CFArrayGetCount(cfDevices)
        for i in 0..<count {
            guard let ptr = CFArrayGetValueAtIndex(cfDevices, i) else { continue }
            let device = OpaquePointer(ptr)
            register(device, mtFrameCallback)
            startDev(device, 0)
            mtDevices.append(device)
        }
        print("[TrackpadService] Registered \(mtDevices.count) multitouch device(s)")
    }

    func stop() {
        for m in eventMonitors { NSEvent.removeMonitor(m) }
        eventMonitors.removeAll()
        if let stopDev = _MTDeviceStop {
            for dev in mtDevices { stopDev(dev) }
        }
        mtDevices.removeAll()
        runLoopSource = nil
        _sharedTrackpadService = nil
        candidateOverlay.hide()
        holdTimerID &+= 1
        fingerDown = false
        prevFingerCount = 0
        isTouching = false
        isEngaged = false
        touchPhase = .idle
    }

    deinit { stop() }

    // MARK: - Helpers

    /// True while a finger is physically resting on the trackpad (used by the
    /// mouse trigger to distinguish a real mouse click from a trackpad tap/click).
    var hasFingerContact: Bool { lastFingerSize >= clickFingerPresenceThreshold }

    /// Returns true if the cursor is currently over one of our app's windows.
    private func isMouseOverOwnWindow() -> Bool {
        let mouseLoc = NSEvent.mouseLocation
        for window in NSApp.windows {
            guard window.isVisible, window.isOnActiveSpace,
                  window !== candidateOverlay.overlayWindow else { continue }
            if window.frame.contains(mouseLoc) { return true }
        }
        return false
    }

    // MARK: - Multitouch callback (finger on / finger off)

    func handleMultitouch(fingerCount: Int32, touchPosition: CGPoint? = nil, size: Float = 0, density: Float = 0) {
        // DIAG: track latest + peak finger pressure metrics for tap-vs-click analysis.
        lastFingerSize = size
        lastFingerDensity = density
        if fingerCount >= 1 {
            peakFingerSize = max(peakFingerSize, size)
            peakFingerDensity = max(peakFingerDensity, density)
        }
        // Skip if mouse is over our own window (let settings panel work normally).
        if isMouseOverOwnWindow() && !isEngaged { return }

        let prev = prevFingerCount
        prevFingerCount = fingerCount

        // 0 → 1: single finger just touched.
        if prev == 0 && fingerCount == 1 && !fingerDown {
            peakFingerSize = size
            peakFingerDensity = density
            if isEngaged {
                // Overlay is showing — record position for tap detection.
                fingerDown = true
                engagedTouchStart = NSEvent.mouseLocation
                return
            }

            // Check activation zone — reject touches near left/right trackpad edges.
            if let pos = touchPosition {
                let margin = CGFloat((settings?.activationMargin ?? 0) / 100.0)
                if margin > 0 {
                    if pos.x < margin || pos.x > (1 - margin) {
                        return  // touch outside activation zone
                    }
                }
            }

            // Respect trackpad-trigger toggle.
            if settings?.trackpadEnabled == false { return }

            // Suppress if typing is active.
            if shouldSuppressActivation?() == true { return }

            fingerDown = true
            candidateMoveDistance = 0
            let nsLoc = NSEvent.mouseLocation
            if let screen = NSScreen.main {
                lastCandidateScreen = CGPoint(x: nsLoc.x, y: screen.frame.height - nsLoc.y)
            }
            let trigger = settings?.activationTrigger ?? .tapToClick
            if trigger == .tapToClick {
                print("[TrackpadService] MT: finger down (0→1), starting hold timer")
                let cursorPt = NSEvent.mouseLocation
                let holdDur = settings?.activationHoldDuration ?? 0.6
                let ringDel = settings?.ringDelay ?? 0.25
                candidateOverlay.show(at: cursorPt, duration: holdDur, delay: ringDel)
                startHoldTimer()
            } else {
                print("[TrackpadService] MT: finger down (0→1), waiting for \(trigger.rawValue)")
            }
            tzLog.info("MT down 0→1: trigger=\(trigger.rawValue, privacy: .public)")
        }
        // N → 0: all fingers lifted.
        else if fingerCount == 0 && fingerDown {
            print("[TrackpadService] MT: all fingers up (\(prev)→0), engaged=\(isEngaged)")
            fingerDown = false
            if isEngaged {
                let liftMode = settings?.liftToSelect ?? true
                tzLog.info("MT up →0 while engaged: liftMode=\(liftMode, privacy: .public) justEngaged=\(self.justEngaged, privacy: .public) → \(liftMode ? "pendingClick(finalize)" : "clickToSelect", privacy: .public)")
                if liftMode {
                    // Lift-to-select: ANY lift while engaged confirms selection.
                    pendingClick = true
                } else if justEngaged {
                    // Click-to-select: first lift after activation — NOT a click.
                    justEngaged = false
                } else {
                    // Click-to-select: only count as tap if cursor barely moved.
                    let cur = NSEvent.mouseLocation
                    let dx = cur.x - engagedTouchStart.x
                    let dy = cur.y - engagedTouchStart.y
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist < 20 {
                        pendingClick = true
                    }
                }
                // Don't disengage.
            } else {
                cancelCandidate()
            }
        }
        // 1 → 2+: extra fingers during candidate → cancel (multi-finger gesture).
        else if prev == 1 && fingerCount > 1 && fingerDown && !isEngaged {
            print("[TrackpadService] MT: multi-finger (\(prev)→\(fingerCount)), cancelling")
            cancelCandidate()
        }
    }

    // MARK: - Global event monitoring (read-only, no Accessibility needed)

    private func handleGlobalEvent(_ event: NSEvent) {
        switch event.type {

        case .mouseMoved:
            if fingerDown && !isEngaged {
                let loc = event.locationInWindow  // CGPoint in screen coords via global monitor
                let screenLoc = CGPoint(x: event.cgEvent?.location.x ?? 0,
                                       y: event.cgEvent?.location.y ?? 0)
                let dx = abs(screenLoc.x - lastCandidateScreen.x)
                let dy = abs(screenLoc.y - lastCandidateScreen.y)
                candidateMoveDistance += dx + dy
                lastCandidateScreen = screenLoc
                if candidateMoveDistance > 3 { cancelCandidate() }
            }

        case .leftMouseDragged:
            if fingerDown && !isEngaged {
                let screenLoc = CGPoint(x: event.cgEvent?.location.x ?? 0,
                                       y: event.cgEvent?.location.y ?? 0)
                let dx = abs(screenLoc.x - lastCandidateScreen.x)
                let dy = abs(screenLoc.y - lastCandidateScreen.y)
                candidateMoveDistance += dx + dy
                lastCandidateScreen = screenLoc
                if candidateMoveDistance > 3 { cancelCandidate() }
            }

        case .leftMouseDown:
            if isEngaged { return }
            let trigger = settings?.activationTrigger ?? .tapToClick
            tzLog.info("leftMouseDown recv: trigger=\(trigger.rawValue, privacy: .public) size=\(self.lastFingerSize, privacy: .public)/peak\(self.peakFingerSize, privacy: .public)")
            if trigger == .click {
                if lastFingerSize < clickFingerPresenceThreshold {
                    tzLog.info("leftMouseDown ignored — tap, no finger contact (size=\(self.lastFingerSize, privacy: .public))")
                    return
                }
                if shouldSuppressActivation?() != true, !isMouseOverOwnWindow(),
                   settings?.trackpadEnabled != false {
                    fingerDown = true
                    candidateMoveDistance = 0
                    let nsLoc = NSEvent.mouseLocation
                    if let screen = NSScreen.main {
                        lastCandidateScreen = CGPoint(x: nsLoc.x, y: screen.frame.height - nsLoc.y)
                    }
                    let holdDur = settings?.activationHoldDuration ?? 0.6
                    let ringDel = settings?.ringDelay ?? 0.25
                    candidateOverlay.show(at: nsLoc, duration: holdDur, delay: ringDel)
                    startHoldTimer()
                    tzLog.info("leftMouseDown → click hold started (\(holdDur, privacy: .public)s)")
                }
                return
            }
            // tapToClick: a click during the hold cancels activation.
            if fingerDown && trigger == .tapToClick { cancelCandidate() }

        case .leftMouseUp:
            // Can't swallow with global monitor — event reaches its target regardless.
            // Candidate/engaged state is managed by MT finger-lift, not mouse-up.
            break

        case .rightMouseDown, .rightMouseUp:
            if isEngaged { /* can't swallow, but can disengage if needed */ }

        case .scrollWheel:
            if isEngaged { return }
            if fingerDown { cancelCandidate() }

        default:
            break
        }
    }

    // MARK: - Hold timer

    private func startHoldTimer() {
        holdTimerID &+= 1
        let capturedID = holdTimerID
        let holdDur = settings?.activationHoldDuration ?? 0.6

        DispatchQueue.main.asyncAfter(deadline: .now() + holdDur) { [weak self] in
            guard let self, self.holdTimerID == capturedID else { return }
            guard self.fingerDown, !self.isEngaged else { return }
            // Check if activation should be suppressed (e.g. typing).
            if self.shouldSuppressActivation?() == true {
                self.cancelCandidate()
                return
            }
            self.engage()
        }
    }

    private func cancelCandidate() {
        holdTimerID &+= 1
        fingerDown = false
        candidateOverlay.hide()
        if isTouching && !isEngaged {
            isTouching = false
            touchPhase = .cancelled
            phaseQueue.append(.cancelled)
        }
    }

    // MARK: - Engagement

    private func engage() {
        print("[TrackpadService] ENGAGED — cursor free, clicks suppressed")
        tzLog.info("ENGAGED — overlay opening")
        candidateOverlay.hide()
        isTouching = true
        isEngaged = true
        justEngaged = true
        touchPhase = .began
        phaseQueue.append(.began)
    }

    // MARK: - Touch end (called by SessionEngine to dismiss overlay)

    func disengage() {
        print("[TrackpadService] DISENGAGED")
        holdTimerID &+= 1
        fingerDown = false
        isTouching = false
        isEngaged = false
        pendingClick = false
        justEngaged = false
        touchPhase = .ended
        phaseQueue.append(.ended)
    }

    /// API compatibility — triggers immediate engagement (used by keyboard shortcut).
    func engage(external: Bool) {
        guard !isEngaged else { return }
        engage()
    }

    /// Called by SessionEngine when the hotkey is released — confirms the current selection.
    func triggerExternalRelease() {
        guard isEngaged else { return }
        pendingClick = true
    }
}
