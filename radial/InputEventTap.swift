import AppKit
import ApplicationServices
import CoreGraphics
import os

private var tapLog: Logger { RadialLog.mouse }

/// C trampoline — an event tap callback cannot capture context, so the owning
/// `InputEventTap` is carried across in `refcon`.
private func inputEventTapCallback(proxy: CGEventTapProxy,
                                   type: CGEventType,
                                   event: CGEvent,
                                   refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputEventTap>.fromOpaque(refcon)
        .takeUnretainedValue()
        .handle(type: type, event: event)
}

/// Active event tap that lets Radial *consume* the input it treats as its own.
///
/// The trigger services observe input through `NSEvent` global monitors, which
/// are read-only: they cannot stop an event from also reaching the focused app.
/// That is why a click used to open or confirm the menu also landed in the app
/// underneath and collapsed the user's text selection, and why the menu-switch
/// key was typed into whatever field had focus.
///
/// Requires Accessibility permission. Without it the tap never starts and the
/// previous pass-through behaviour remains, so the monitors stay in place as a
/// fallback.
final class InputEventTap {

    /// Called for every tapped event. Return true to consume it.
    ///
    /// A consumed event is deleted from the stream, so it never reaches our own
    /// global monitors either — the handler must therefore perform whatever
    /// work those monitors would have done for the events it swallows.
    var shouldConsume: ((CGEventType, CGEvent) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// False when Accessibility permission is missing, the port is invalid, or
    /// macOS has disabled the tap.
    var isActive: Bool {
        guard let tap, CFMachPortIsValid(tap) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    // MARK: - Lifecycle

    func start() {
        guard tap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)  |
            (1 << CGEventType.leftMouseUp.rawValue)    |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)   |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)   |
            (1 << CGEventType.keyDown.rawValue)        |
            (1 << CGEventType.keyUp.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: inputEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapLog.error("InputEventTap could not start — Accessibility permission missing; input will keep passing through to the focused app")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        tapLog.info("InputEventTap started")
    }

    func stop() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let src = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        tap = nil
        source = nil
    }

    /// Heartbeat recovery for event taps, whose validity and enabled state are
    /// queryable (unlike AppKit global-monitor tokens).
    @discardableResult
    func repairIfNeeded() -> Bool {
        guard let tap else {
            // Missing Accessibility permission is an intentional fallback, not
            // a broken listener. Retry automatically once permission exists.
            guard AXIsProcessTrusted() else { return false }
            start()
            return isActive
        }

        if CFMachPortIsValid(tap), !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                tapLog.info("InputEventTap heartbeat re-enabled disabled tap")
                return true
            }
        }

        guard !CFMachPortIsValid(tap) || !CGEvent.tapIsEnabled(tap: tap) else { return false }
        stop()
        start()
        tapLog.info("InputEventTap heartbeat rebuilt invalid tap")
        return true
    }

    deinit { stop() }

    // MARK: - Callback

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that blocks for too long, and after some
        // permission changes. Re-arm it rather than silently going deaf.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            tapLog.info("InputEventTap re-enabled after being disabled by the system")
            return Unmanaged.passUnretained(event)
        }

        if shouldConsume?(type, event) == true { return nil }
        return Unmanaged.passUnretained(event)
    }
}
