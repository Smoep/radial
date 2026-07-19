import Foundation

/// A single executable action within a radial category.
/// If `children` is non-empty, acts as a subcategory that opens another ring.
struct RadialAction: Codable, Identifiable {
    var id: String           // e.g. "media.playPause"
    var label: String        // e.g. "Play/Pause"
    var systemImage: String  // SF Symbol name
    var actionType: ActionType
    var actionConfig: ActionConfig
    var children: [RadialAction]?

    /// True if this action opens a deeper ring instead of executing.
    var isSubcategory: Bool { children != nil }

    struct ActionConfig: Codable {
        // Keyboard shortcut
        var keyCode: Int?
        var keyChar: String?
        var keyLabel: String?
        var useCommand: Bool?
        var useShift: Bool?
        var useOption: Bool?
        var useControl: Bool?
        // App launch
        var appPath: String?
        /// When true, an Open Application action shows the app's own icon
        /// instead of the chosen SF Symbol.
        var useAppIcon: Bool?
        // macOS Shortcuts app
        var shortcutName: String?
        // Shell command
        var shellCommand: String?
        // Media
        var mediaAction: MediaActionType?
    }

    /// Convert to ActionMapping for execution.
    var asMapping: ActionMapping {
        var m = ActionMapping(id: id, actionType: actionType)
        m.keyCode     = actionConfig.keyCode ?? -1
        m.keyChar     = actionConfig.keyChar ?? ""
        m.keyLabel    = actionConfig.keyLabel ?? ""
        m.useCommand  = actionConfig.useCommand ?? false
        m.useShift    = actionConfig.useShift ?? false
        m.useOption   = actionConfig.useOption ?? false
        m.useControl  = actionConfig.useControl ?? false
        m.appPath     = actionConfig.appPath ?? ""
        m.shortcutName = actionConfig.shortcutName ?? ""
        m.shellCommand = actionConfig.shellCommand ?? ""
        m.mediaAction = actionConfig.mediaAction ?? .playPause
        return m
    }
}

/// A category shown as a slice in the inner ring.
struct RadialCategory: Codable, Identifiable {
    var id: String           // e.g. "media"
    var label: String        // e.g. "Media"
    var systemImage: String  // SF Symbol
    var colorHex: String     // Hex color for the slice
    var actions: [RadialAction]
}

/// Persistent store for the radial menu categories and actions.
@Observable
final class RadialMenuStore {

    static let shared = RadialMenuStore()

    var categories: [RadialCategory] = [] {
        didSet { save() }
    }

    private let storageKey = "radialMenuCategories"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RadialCategory].self, from: data) {
            categories = decoded
        } else {
            categories = Self.defaultCategories
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Reset to defaults.
    func resetToDefaults() {
        categories = Self.defaultCategories
    }

    /// Access an action by path: [catIdx, actIdx, subIdx, ...].
    func actionAt(path: [Int]) -> RadialAction? {
        guard path.count >= 2, path[0] < categories.count else { return nil }
        var items = categories[path[0]].actions
        for d in 1..<path.count {
            guard path[d] < items.count else { return nil }
            if d == path.count - 1 { return items[path[d]] }
            items = items[path[d]].children ?? []
        }
        return nil
    }

    /// Set an action at path.
    func setAction(_ action: RadialAction, at path: [Int]) {
        guard path.count >= 2, path[0] < categories.count else { return }
        if path.count == 2 {
            categories[path[0]].actions[path[1]] = action
            return
        }
        setActionRecursive(&categories[path[0]].actions, action: action, path: Array(path.dropFirst()), depth: 0)
    }

    private func setActionRecursive(_ actions: inout [RadialAction], action: RadialAction, path: [Int], depth: Int) {
        guard path[depth] < actions.count else { return }
        if depth == path.count - 1 {
            actions[path[depth]] = action
            return
        }
        var children = actions[path[depth]].children ?? []
        setActionRecursive(&children, action: action, path: path, depth: depth + 1)
        actions[path[depth]].children = children
    }

    /// Remove an action at path.
    func removeAction(at path: [Int]) {
        guard path.count >= 2, path[0] < categories.count else { return }
        if path.count == 2 {
            categories[path[0]].actions.remove(at: path[1])
            return
        }
        removeActionRecursive(&categories[path[0]].actions, path: Array(path.dropFirst()), depth: 0)
    }

    private func removeActionRecursive(_ actions: inout [RadialAction], path: [Int], depth: Int) {
        guard path[depth] < actions.count else { return }
        if depth == path.count - 1 {
            actions.remove(at: path[depth])
            return
        }
        var children = actions[path[depth]].children ?? []
        removeActionRecursive(&children, path: path, depth: depth + 1)
        actions[path[depth]].children = children
    }

    /// Append an action at path (path is the parent: [catIdx] or [catIdx, actIdx, ...]).
    func appendAction(_ action: RadialAction, at parentPath: [Int]) {
        guard !parentPath.isEmpty, parentPath[0] < categories.count else { return }
        if parentPath.count == 1 {
            categories[parentPath[0]].actions.append(action)
            return
        }
        appendActionRecursive(&categories[parentPath[0]].actions, action: action,
                              path: Array(parentPath.dropFirst()), depth: 0)
    }

    private func appendActionRecursive(_ actions: inout [RadialAction], action: RadialAction,
                                        path: [Int], depth: Int) {
        guard path[depth] < actions.count else { return }
        if depth == path.count - 1 {
            if actions[path[depth]].children == nil {
                actions[path[depth]].children = []
            }
            actions[path[depth]].children!.append(action)
            return
        }
        var children = actions[path[depth]].children ?? []
        appendActionRecursive(&children, action: action, path: path, depth: depth + 1)
        actions[path[depth]].children = children
    }

    /// Move an action within its sibling list at the given parent path.
    func moveAction(atParentPath parentPath: [Int], from: Int, to: Int) {
        guard !parentPath.isEmpty, parentPath[0] < categories.count else { return }
        if parentPath.count == 1 {
            // Top-level actions in a category.
            let item = categories[parentPath[0]].actions.remove(at: from)
            categories[parentPath[0]].actions.insert(item, at: to > from ? to : to)
            return
        }
        // Deeper: walk to the parent and move within its children.
        moveActionRecursive(&categories[parentPath[0]].actions,
                            path: Array(parentPath.dropFirst()), depth: 0,
                            from: from, to: to)
    }

    private func moveActionRecursive(_ actions: inout [RadialAction],
                                      path: [Int], depth: Int,
                                      from: Int, to: Int) {
        guard path[depth] < actions.count else { return }
        if depth == path.count - 1 {
            guard var children = actions[path[depth]].children else { return }
            let item = children.remove(at: from)
            children.insert(item, at: to > from ? to : to)
            actions[path[depth]].children = children
            return
        }
        var children = actions[path[depth]].children ?? []
        moveActionRecursive(&children, path: path, depth: depth + 1, from: from, to: to)
        actions[path[depth]].children = children
    }

    // MARK: - Default categories

    static let defaultCategories: [RadialCategory] = [
        RadialCategory(
            id: "media", label: "Media", systemImage: "play.circle.fill",
            colorHex: "#34C759",
            actions: [
                RadialAction(id: "media.playPause", label: "Play/Pause", systemImage: "playpause.fill",
                             actionType: .mediaControl,
                             actionConfig: .init(mediaAction: .playPause)),
                RadialAction(id: "media.next", label: "Next", systemImage: "forward.fill",
                             actionType: .mediaControl,
                             actionConfig: .init(mediaAction: .nextTrack)),
                RadialAction(id: "media.prev", label: "Previous", systemImage: "backward.fill",
                             actionType: .mediaControl,
                             actionConfig: .init(mediaAction: .prevTrack)),
                RadialAction(id: "media.volUp", label: "Vol Up", systemImage: "speaker.plus.fill",
                             actionType: .mediaControl,
                             actionConfig: .init(mediaAction: .volumeUp)),
                RadialAction(id: "media.volDown", label: "Vol Down", systemImage: "speaker.minus.fill",
                             actionType: .mediaControl,
                             actionConfig: .init(mediaAction: .volumeDown)),
                RadialAction(id: "media.mute", label: "Mute", systemImage: "speaker.slash.fill",
                             actionType: .mediaControl,
                             actionConfig: .init(mediaAction: .mute)),
            ]
        ),
        RadialCategory(
            id: "apps", label: "Apps", systemImage: "square.grid.2x2.fill",
            colorHex: "#007AFF",
            actions: [
                RadialAction(id: "apps.safari", label: "Safari", systemImage: "safari.fill",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "Safari")),
                RadialAction(id: "apps.finder", label: "Finder", systemImage: "folder.fill",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "Finder")),
                RadialAction(id: "apps.terminal", label: "Terminal", systemImage: "terminal.fill",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "Terminal")),
                RadialAction(id: "apps.messages", label: "Messages", systemImage: "message.fill",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "Messages")),
                RadialAction(id: "apps.mail", label: "Mail", systemImage: "envelope.fill",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "Mail")),
                RadialAction(id: "apps.notes", label: "Notes", systemImage: "note.text",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "Notes")),
            ]
        ),
        RadialCategory(
            id: "windows", label: "Windows", systemImage: "macwindow",
            colorHex: "#FF9500",
            actions: [
                RadialAction(id: "win.minimize", label: "Minimize", systemImage: "minus.square",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 46, keyChar: "m", keyLabel: "M", useCommand: true)),
                RadialAction(id: "win.close", label: "Close", systemImage: "xmark.square",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 13, keyChar: "w", keyLabel: "W", useCommand: true)),
                RadialAction(id: "win.fullscreen", label: "Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 3, keyChar: "f", keyLabel: "F", useCommand: true, useControl: true)),
                RadialAction(id: "win.mission", label: "Mission Ctrl", systemImage: "rectangle.3.group",
                             actionType: .shellCommand,
                             actionConfig: .init(shellCommand: "osascript -e 'tell application \"Mission Control\" to launch'")),
                RadialAction(id: "win.hide", label: "Hide", systemImage: "eye.slash",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 4, keyChar: "h", keyLabel: "H", useCommand: true)),
                RadialAction(id: "win.quit", label: "Quit App", systemImage: "power",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 12, keyChar: "q", keyLabel: "Q", useCommand: true)),
            ]
        ),
        RadialCategory(
            id: "system", label: "System", systemImage: "gearshape.fill",
            colorHex: "#AF52DE",
            actions: [
                RadialAction(id: "sys.screenshot", label: "Screenshot", systemImage: "camera.viewfinder",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 23, keyChar: "5", keyLabel: "5", useCommand: true, useShift: true)),
                RadialAction(id: "sys.spotlight", label: "Spotlight", systemImage: "magnifyingglass",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 49, keyLabel: "Space", useCommand: true)),
                RadialAction(id: "sys.dnd", label: "Do Not Disturb", systemImage: "moon.fill",
                             actionType: .shellCommand,
                             actionConfig: .init(shellCommand: "shortcuts run \"Toggle Do Not Disturb\"")),
                RadialAction(id: "sys.lock", label: "Lock Screen", systemImage: "lock.fill",
                             actionType: .keyboardShortcut,
                             actionConfig: .init(keyCode: 12, keyChar: "q", keyLabel: "Q", useCommand: true, useControl: true)),
            ]
        ),
        RadialCategory(
            id: "chinese-test", label: "中文测试", systemImage: "character.bubble.fill",
            colorHex: "#00A6A6",
            actions: [
                RadialAction(id: "chinese-test.settings", label: "设置", systemImage: "gearshape.fill",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "System Settings")),
                RadialAction(id: "chinese-test.browser", label: "打开浏览器", systemImage: "safari.fill",
                             actionType: .openApplication,
                             actionConfig: .init(appPath: "Safari")),
                RadialAction(id: "chinese-test.music", label: "音乐播放控制", systemImage: "playpause.fill",
                             actionType: .mediaControl,
                             actionConfig: .init(mediaAction: .playPause)),
                RadialAction(id: "chinese-test.duplicate-tab", label: "复制当前标签页", systemImage: "rectangle.on.rectangle",
                             actionType: .shortcutsApp,
                             actionConfig: .init(shortcutName: "Duplicate Tab")),
            ]
        ),
    ]
}
