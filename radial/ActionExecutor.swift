import Foundation
import CoreGraphics
import AppKit

/// Executes actions mapped to gesture cells.
enum ActionExecutor {

    static func execute(_ mapping: ActionMapping) {
        switch mapping.actionType {
        case .keyboardShortcut: sendKeyboardShortcut(mapping)
        case .openApplication: openApplication(mapping.appPath)
        case .shortcutsApp:    runShortcut(named: mapping.shortcutName)
        case .shellCommand:    runShellCommand(mapping.shellCommand)
        case .mediaControl:    sendMediaKey(mapping.mediaAction)
        case .automation:      runAutomation(mapping.automationSteps ?? [])
        }
    }

    // MARK: - Automation

    /// Maximum allowed delay between steps (matches the editor's slider cap).
    private static let maxStepDelayMs = 20_000

    /// Run each step in order, sleeping the step's delay before the next one.
    /// Runs on a detached task so the overlay dismisses immediately; each step
    /// is dispatched to the main actor to match the single-action call path.
    private static func runAutomation(_ steps: [AutomationStep]) {
        // Guard against nested automations to avoid recursion.
        let steps = steps.filter { $0.actionType != .automation }
        guard !steps.isEmpty else { return }
        Task.detached {
            for (index, step) in steps.enumerated() {
                let mapping = step.asMapping
                await MainActor.run { execute(mapping) }
                guard index < steps.count - 1 else { break }
                let ms = min(max(step.delayAfterMs, 0), maxStepDelayMs)
                if ms > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                }
            }
        }
    }

    // MARK: - Shortcuts App

    private static func runShortcut(named name: String) {
        guard !name.isEmpty else { return }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    // MARK: - Keyboard Shortcut

    private static func sendKeyboardShortcut(_ mapping: ActionMapping) {
        // Prefer the raw key code recorded directly; fall back to name-based lookup.
        let keyCode: UInt16
        if mapping.keyCode >= 0 {
            keyCode = UInt16(mapping.keyCode)
        } else if let mapped = keyCodeMap[mapping.keyChar.lowercased()] {
            keyCode = mapped
        } else {
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        if mapping.useCommand { flags.insert(.maskCommand) }
        if mapping.useShift   { flags.insert(.maskShift) }
        if mapping.useOption  { flags.insert(.maskAlternate) }
        if mapping.useControl { flags.insert(.maskControl) }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    // macOS virtual key codes for common keys.
    private static let keyCodeMap: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, " ": 49, "`": 50, "space": 49,
        "return": 36, "tab": 48, "escape": 53, "delete": 51,
        "up": 126, "down": 125, "left": 123, "right": 124,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
        "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111,
    ]

    // MARK: - Open Application

    private static func openApplication(_ path: String) {
        guard !path.isEmpty else { return }
        if path.hasPrefix("/") {
            runShellCommand("open '\(path.replacingOccurrences(of: "'", with: "'\\''"  ))'")
        } else {
            runShellCommand("open -a '\(path.replacingOccurrences(of: "'", with: "'\\''"  ))'")
        }
    }

    // MARK: - Shell Command

    private static func runShellCommand(_ command: String) {
        guard !command.isEmpty else { return }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError  = FileHandle.nullDevice
            try? process.run()
        }
    }

    // MARK: - Media Control

    private static func sendMediaKey(_ action: MediaActionType) {
        let keyType: Int32
        switch action {
        case .playPause:  keyType = 16   // NX_KEYTYPE_PLAY
        case .nextTrack:  keyType = 17   // NX_KEYTYPE_NEXT
        case .prevTrack:  keyType = 18   // NX_KEYTYPE_PREVIOUS
        case .volumeUp:   keyType = 0    // NX_KEYTYPE_SOUND_UP
        case .volumeDown: keyType = 1    // NX_KEYTYPE_SOUND_DOWN
        case .mute:       keyType = 7    // NX_KEYTYPE_MUTE
        }
        postSystemKeyEvent(keyType: keyType, keyDown: true)
        postSystemKeyEvent(keyType: keyType, keyDown: false)
    }

    private static func postSystemKeyEvent(keyType: Int32, keyDown: Bool) {
        let flags: Int32 = keyDown ? 0x0A00 : 0x0B00
        let data1 = Int((keyType << 16) | Int32(flags))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
