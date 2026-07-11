import Foundation
import AppKit
import Observation

enum HotkeyMode: String, CaseIterable, Identifiable {
    case combo     = "Combo"
    case doubleTap = "Double Tap"
    var id: String { rawValue }
}

/// Which mouse button opens the radial overlay.
enum MouseButton: String, CaseIterable, Identifiable {
    case left   = "Left"
    case middle = "Middle"
    var id: String { rawValue }

    /// NSEvent buttonNumber: left = 0, right = 1, middle = 2.
    var buttonNumber: Int {
        switch self {
        case .left:   0
        case .middle: 2
        }
    }
}

/// What physical gesture opens the radial overlay, ordered by increasing click depth.
enum ActivationTrigger: String, CaseIterable, Identifiable {
    /// Touch and hold still — no physical click (current default).
    case tapToClick
    /// Physically click the trackpad.
    case click

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tapToClick: "Tap to Click"
        case .click:      "Click"
        }
    }

    var help: String {
        switch self {
        case .tapToClick: "Touch and hold to open the menu"
        case .click:      "Click the trackpad to open the menu"
        }
    }
}

/// All user-configurable parameters, persisted to UserDefaults with debounced writes.
@Observable
final class AppSettings {

    private var saveTimer: Timer?

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.persistAll()
        }
    }

    private func persistAll() {
        let d = UserDefaults.standard
        d.set(activationHoldDuration, forKey: "activationHoldDuration")
        d.set(gridDivisions, forKey: "gridDivisions")
        d.set(dragRange, forKey: "dragRange")
        d.set(ringDelay, forKey: "ringDelay")
        d.set(liftToSelect, forKey: "liftToSelect")
        d.set(isTestMode, forKey: "isTestMode")
        d.set(activationMargin, forKey: "activationMargin")
        d.set(ringHeight, forKey: "ringHeight")
        d.set(selectionWidth, forKey: "selectionWidth")
        d.set(categoryFlexibilityPercent, forKey: "categoryFlexibilityPercent")
        d.set(pauseWhileTyping, forKey: "pauseWhileTyping")
        d.set(activationTrigger.rawValue, forKey: "activationTrigger")
        d.set(overlayOpacity, forKey: "overlayOpacity")
        d.set(hotkeyEnabled,  forKey: "hotkeyEnabled")
        d.set(hotkeyKeyCode,  forKey: "hotkeyKeyCode")
        d.set(hotkeyModifiers, forKey: "hotkeyModifiers")
        d.set(hotkeyKeyLabel, forKey: "hotkeyKeyLabel")
        d.set(hotkeyMode.rawValue, forKey: "hotkeyMode")
        d.set(doubleTapWindow, forKey: "doubleTapWindow")
        d.set(trackpadEnabled, forKey: "trackpadEnabled")
        d.set(mouseEnabled, forKey: "mouseEnabled")
        d.set(mouseButton.rawValue, forKey: "mouseButton")
        d.set(mouseHoldDuration, forKey: "mouseHoldDuration")
        d.set(mouseReleaseToSelect, forKey: "mouseReleaseToSelect")
    }

    // MARK: - Activation

    /// Whether the trackpad/mouse trigger is active.
    var trackpadEnabled: Bool = true {
        didSet { scheduleSave() }
    }

    /// Which physical gesture opens the overlay (tap-to-click / click / force-click).
    var activationTrigger: ActivationTrigger = .tapToClick {
        didSet { scheduleSave() }
    }

    // MARK: - Mouse trigger

    /// Whether the mouse-button trigger is active.
    var mouseEnabled: Bool = false {
        didSet { scheduleSave() }
    }

    /// Which mouse button opens the overlay.
    var mouseButton: MouseButton = .middle {
        didSet { scheduleSave() }
    }

    /// Hold time (seconds) before the mouse click engages. 0 = immediate.
    var mouseHoldDuration: Double = 0.0 {
        didSet { scheduleSave() }
    }

    /// When true, releasing the mouse button while engaged confirms the selection.
    /// When false, a separate click confirms.
    var mouseReleaseToSelect: Bool = true {
        didSet { scheduleSave() }
    }

    /// Minimum touch hold time (seconds) before entering Active.
    var activationHoldDuration: Double = 0.60 {
        didSet { scheduleSave() }
    }

    // MARK: - Grid

    /// Grid divisions per axis (e.g. 3 = 3×3, 4 = 4×4). Range 2–6.
    var gridDivisions: Int = 3 {
        didSet { scheduleSave() }
    }

    // MARK: - Sensitivity

    /// Drag distance in points to cover the full 0–1 range. Lower = more sensitive.
    var dragRange: Double = 200 {
        didSet { scheduleSave() }
    }

    /// Delay in seconds before the candidate ring animation appears.
    var ringDelay: Double = 0.25 {
        didSet { scheduleSave() }
    }

    // MARK: - Mode

    /// When true, lifting the finger while engaged immediately confirms the selection.
    /// When false, lifting keeps the overlay open and a separate click confirms.
    var liftToSelect: Bool = true {
        didSet { scheduleSave() }
    }

    /// When true, system actions are suppressed; safe for testing.
    var isTestMode: Bool = true {
        didSet { scheduleSave() }
    }

    /// Activation zone: 0–40 percent margin from trackpad edges (0 = full trackpad, 30 = center 40%).
    var activationMargin: Double = 0 {
        didSet { scheduleSave() }
    }

    // MARK: - Overlay

    /// Radial thickness of each ring (points).
    var ringHeight: Double = 60 {
        didSet { scheduleSave() }
    }

    /// Arc-length per item in deeper rings (points). Controls how wide each action/folder slice is.
    var selectionWidth: Double = 45 {
        didSet { scheduleSave() }
    }

    /// Percentage of the first ring where the selected category can still change.
    var categoryFlexibilityPercent: Double = 0 {
        didSet { scheduleSave() }
    }

    /// Overall opacity of the radial overlay window (0.3–1.0).
    var overlayOpacity: Double = 1.0 {
        didSet { scheduleSave() }
    }

    /// When true, tracking is paused while the user is typing.
    var pauseWhileTyping: Bool = true {
        didSet { scheduleSave() }
    }

    // MARK: - Hotkey

    /// Whether a keyboard shortcut can trigger the overlay.
    var hotkeyEnabled: Bool = false {
        didSet { scheduleSave() }
    }

    /// Virtual key code of the shortcut (-1 = none).
    var hotkeyKeyCode: Int = -1 {
        didSet { scheduleSave() }
    }

    /// NSEvent.ModifierFlags.rawValue (stored as Int) for the shortcut.
    var hotkeyModifiers: Int = 0 {
        didSet { scheduleSave() }
    }

    /// Human-readable label for the key portion, e.g. "F7" or "Space".
    var hotkeyKeyLabel: String = "" {
        didSet { scheduleSave() }
    }

    /// Trigger on key combo once, or double-tap the same key.
    var hotkeyMode: HotkeyMode = .combo {
        didSet { scheduleSave() }
    }

    /// Time window (seconds) within which two taps count as a double-tap.
    var doubleTapWindow: Double = 0.35 {
        didSet { scheduleSave() }
    }

    /// Full display string, e.g. "⌘⇧K" or "⌘ ⌘".
    var hotkeyDisplayString: String {
        guard hotkeyKeyCode >= 0, !hotkeyKeyLabel.isEmpty else { return "Not set" }
        if hotkeyMode == .doubleTap { return "\(hotkeyKeyLabel) \(hotkeyKeyLabel)" }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + hotkeyKeyLabel
    }

    // MARK: - Modifier key helpers

    static let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
    static func isModifierKeyCode(_ code: Int) -> Bool { modifierKeyCodes.contains(code) }

    static func modifierFlagForKeyCode(_ code: Int) -> NSEvent.ModifierFlags {
        switch code {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        default: return []
        }
    }

    static func modifierKeyLabel(_ code: Int) -> String {
        switch code {
        case 54, 55: return "⌘"
        case 56, 60: return "⇧"
        case 58, 61: return "⌥"
        case 59, 62: return "⌃"
        case 57:     return "⇪"
        default: return "?"
        }
    }

    // MARK: - Singleton

    static let shared = AppSettings()

    private init() {
        let d = UserDefaults.standard
        if let v = d.object(forKey: "activationHoldDuration") as? Double { activationHoldDuration = v }
        if let v = d.object(forKey: "gridDivisions")     as? Int    { gridDivisions     = v }
        if let v = d.object(forKey: "dragRange")         as? Double { dragRange         = v }
        if let v = d.object(forKey: "ringDelay")          as? Double { ringDelay          = v }
        if let v = d.object(forKey: "liftToSelect")      as? Bool   { liftToSelect      = v }
        if let v = d.object(forKey: "isTestMode")        as? Bool   { isTestMode        = v }
        if let v = d.object(forKey: "activationMargin")  as? Double { activationMargin  = v }
        if let v = d.object(forKey: "ringHeight")        as? Double { ringHeight        = v }
        if let v = d.object(forKey: "selectionWidth")    as? Double { selectionWidth    = v }
        if let v = d.object(forKey: "categoryFlexibilityPercent") as? Double {
            categoryFlexibilityPercent = min(max(v, 0), 50)
        }
        if let v = d.object(forKey: "pauseWhileTyping")  as? Bool   { pauseWhileTyping  = v }
        if let v = d.object(forKey: "overlayOpacity")    as? Double { overlayOpacity    = v }
        if let v = d.object(forKey: "activationTrigger") as? String,
           let t = ActivationTrigger(rawValue: v)                   { activationTrigger = t }
        if let v = d.object(forKey: "hotkeyEnabled")  as? Bool   { hotkeyEnabled  = v }
        if let v = d.object(forKey: "hotkeyKeyCode")  as? Int    { hotkeyKeyCode  = v }
        if let v = d.object(forKey: "hotkeyModifiers") as? Int   { hotkeyModifiers = v }
        if let v = d.object(forKey: "hotkeyKeyLabel") as? String { hotkeyKeyLabel  = v }
        if let v = d.object(forKey: "hotkeyMode") as? String,
           let m = HotkeyMode(rawValue: v)            { hotkeyMode = m }
        if let v = d.object(forKey: "doubleTapWindow") as? Double { doubleTapWindow = v }
        if let v = d.object(forKey: "trackpadEnabled") as? Bool   { trackpadEnabled = v }
        if let v = d.object(forKey: "mouseEnabled")    as? Bool   { mouseEnabled    = v }
        if let v = d.object(forKey: "mouseButton") as? String,
           let b = MouseButton(rawValue: v)                       { mouseButton     = b }
        if let v = d.object(forKey: "mouseHoldDuration") as? Double { mouseHoldDuration = v }
        if let v = d.object(forKey: "mouseReleaseToSelect") as? Bool { mouseReleaseToSelect = v }
    }
}
