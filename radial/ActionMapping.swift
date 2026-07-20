import Foundation
import Observation

// MARK: - Types

enum ActionType: String, Codable, CaseIterable {
    case keyboardShortcut = "Keyboard Shortcut"
    case openApplication  = "Open Application"
    case shortcutsApp     = "Shortcuts App"
    case shellCommand     = "Shell Command"
    case mediaControl     = "Media Control"
    case automation       = "Automation"
}

enum MediaActionType: String, Codable, CaseIterable {
    case playPause  = "Play/Pause"
    case nextTrack  = "Next Track"
    case prevTrack  = "Previous Track"
    case volumeUp   = "Volume Up"
    case volumeDown = "Volume Down"
    case mute       = "Mute"
}

// MARK: - Mapping

struct ActionMapping: Codable, Identifiable, Equatable {
    /// Zone identifier (e.g. "Z1", "Z2", …).
    var id: String
    var actionType: ActionType

    // Keyboard shortcut
    var keyChar:    String = ""   // legacy: name like "m", "space", "f1"
    var keyCode:    Int    = -1   // raw macOS CGKeyCode; -1 = use keyChar lookup
    var keyLabel:   String = ""   // display label captured during recording
    var useCommand: Bool   = false
    var useShift:   Bool   = false
    var useOption:  Bool   = false
    var useControl: Bool   = false

    // Open application
    var appPath: String = ""

    // macOS Shortcuts app
    var shortcutName: String = ""

    // Shell command
    var shellCommand: String = ""

    // Media control
    var mediaAction: MediaActionType = .playPause

    // Automation (ordered steps executed with a delay between each)
    var automationSteps: [AutomationStep]? = nil

    var displayDescription: String {
        switch actionType {
        case .keyboardShortcut:
            var mods = ""
            if useControl { mods += "⌃" }
            if useOption  { mods += "⌥" }
            if useShift   { mods += "⇧" }
            if useCommand { mods += "⌘" }
            let key = keyLabel.isEmpty ? keyChar.uppercased() : keyLabel
            return "\(mods)\(key)"
        case .openApplication:
            let name = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            return name.isEmpty ? appPath : name
        case .shortcutsApp:
            return shortcutName.isEmpty ? "Shortcut" : shortcutName
        case .shellCommand:
            let preview = shellCommand.prefix(25)
            return shellCommand.count > 25 ? "\(preview)…" : String(preview)
        case .mediaControl:
            return mediaAction.rawValue
        case .automation:
            let count = automationSteps?.count ?? 0
            return count == 1 ? "1 step" : "\(count) steps"
        }
    }
}

// MARK: - Store

@Observable
final class ActionStore {
    private(set) var mappings: [ActionMapping] = []
    private let storageKey = "actionMappings"

    static let shared = ActionStore()

    private init() { load() }

    func mapping(for zoneID: String) -> ActionMapping? {
        mappings.first { $0.id == zoneID }
    }

    func add(_ mapping: ActionMapping) {
        if let idx = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[idx] = mapping
        } else {
            mappings.append(mapping)
        }
        save()
    }

    func remove(id: String) {
        mappings.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ActionMapping].self, from: data)
        else { return }
        mappings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
