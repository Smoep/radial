import Foundation

/// A single item in a radial menu. Items live at every depth, including the
/// first ring: an item with `children` opens a deeper ring, one without fires.
struct RadialAction: Codable, Identifiable {
    var id: String           // e.g. "media.playPause"
    var label: String        // e.g. "Play/Pause"
    var systemImage: String  // SF Symbol name
    var actionType: ActionType
    var actionConfig: ActionConfig
    var children: [RadialAction]?
    /// Slice colour. `nil` inherits the nearest ancestor's colour.
    var colorHex: String?

    /// True if this action opens a deeper ring instead of executing.
    var isSubcategory: Bool { children != nil }

    /// An independent copy carrying fresh identifiers.
    ///
    /// Every descendant is re-keyed too: ids drive SwiftUI identity, expansion
    /// state and drag paths, so two items sharing one id would misbehave.
    func duplicated() -> RadialAction {
        var copy = self
        copy.id = UUID().uuidString
        copy.children = children?.map { $0.duplicated() }
        return copy
    }

    struct ActionConfig: Codable, Equatable {
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
        // Open folder / file
        var targetPath: String?
        /// When true, an Open Folder/File action shows the target's own Finder
        /// icon instead of the chosen SF Symbol.
        var useFileIcon: Bool?
        // Open URL
        var targetURL: String?
        // macOS Shortcuts app
        var shortcutName: String?
        // Shell command
        var shellCommand: String?
        // Media
        var mediaAction: MediaActionType?
        // Automation (ordered steps run sequentially with a delay between each)
        var automationSteps: [AutomationStep]?
    }

    /// Convert to ActionMapping for execution.
    var asMapping: ActionMapping {
        ActionMapping(actionID: id, type: actionType, config: actionConfig)
    }

    /// The label as the ring should draw it: one element, or two when the user
    /// typed a line break.
    var labelLines: [String] { Self.labelLines(from: label) }

    /// The label flattened onto one line, for list rows and drag previews that
    /// assume single-line text and would otherwise grow a row taller.
    var singleLineLabel: String { Self.singleLine(label) }

    /// Splits a label at an explicit line break.
    ///
    /// The ring draws exactly two curved arcs, so only the first break creates a
    /// line; any further ones become spaces rather than silently dropping text.
    /// A break with nothing on one side collapses back to a single line.
    static func labelLines(from label: String) -> [String] {
        let parts = label.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return [label] }
        let first = parts[0].trimmingCharacters(in: .whitespaces)
        let rest = parts[1...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if first.isEmpty { return [rest] }
        if rest.isEmpty { return [first] }
        return [first, rest]
    }

    static func singleLine(_ label: String) -> String {
        label.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// One step in an Automation action: any action type plus the delay (ms) to
/// wait *after* running it before the next step. The delay is ignored for the
/// final step.
struct AutomationStep: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var actionType: ActionType
    var config: RadialAction.ActionConfig
    var delayAfterMs: Int = 1000

    /// Flattened form used by the executor.
    var asMapping: ActionMapping {
        ActionMapping(actionID: id, type: actionType, config: config)
    }
}

extension ActionMapping {
    /// Build an execution mapping from a stored action type + config.
    init(actionID: String, type: ActionType, config: RadialAction.ActionConfig) {
        self.init(id: actionID, actionType: type)
        keyCode        = config.keyCode ?? -1
        keyChar        = config.keyChar ?? ""
        keyLabel       = config.keyLabel ?? ""
        useCommand     = config.useCommand ?? false
        useShift       = config.useShift ?? false
        useOption      = config.useOption ?? false
        useControl     = config.useControl ?? false
        appPath        = config.appPath ?? ""
        targetPath     = config.targetPath ?? ""
        targetURL      = config.targetURL ?? ""
        shortcutName   = config.shortcutName ?? ""
        shellCommand   = config.shellCommand ?? ""
        mediaAction    = config.mediaAction ?? .playPause
        automationSteps = config.automationSteps
    }
}

/// Legacy first-ring container. Menus used to be `[RadialCategory]`; they are
/// now a flat `[RadialAction]` tree. Kept so stored data and old backups still
/// decode, and so the built-in defaults stay readable.
struct RadialCategory: Codable, Identifiable {
    var id: String           // e.g. "media"
    var label: String        // e.g. "Media"
    var systemImage: String  // SF Symbol
    var colorHex: String     // Hex color for the slice
    var actions: [RadialAction]

    /// A first-ring item holding the category's actions as children.
    var asAction: RadialAction {
        RadialAction(id: id, label: label, systemImage: systemImage,
                     actionType: .keyboardShortcut, actionConfig: .init(),
                     children: actions, colorHex: colorHex)
    }
}

/// Colour used by items that have none and no coloured ancestor.
let radialDefaultColorHex = "#808080"

/// Persistent store for one radial menu.
///
/// A menu is a tree of `RadialAction`s. Items are addressed by an index path:
/// `[]` is the first ring, `[2]` is the third first-ring item, `[2, 0]` its
/// first child, and so on.
///
/// `shared` holds the Global Menu. App-specific menus get their own instance
/// (one per bundle identifier) vended by `AppMenuLibrary`.
@Observable
final class RadialMenuStore {

    /// The Global Menu.
    static let shared = RadialMenuStore(storageKey: "radialMenuCategories", seedDefaults: true)

    /// First-ring items.
    var items: [RadialAction] = [] {
        didSet { save() }
    }

    private let storageKey: String

    init(storageKey: String, seedDefaults: Bool) {
        self.storageKey = storageKey
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            items = Self.decodeMenu(from: data) ?? (seedDefaults ? Self.defaultItems : [])
        } else if seedDefaults {
            items = Self.defaultItems
        }
    }

    /// Decode a menu, migrating the legacy `[RadialCategory]` shape.
    /// `RadialAction` is tried first because it cannot decode category JSON
    /// (`actionType`/`actionConfig` are required), so the two are unambiguous.
    static func decodeMenu(from data: Data) -> [RadialAction]? {
        let decoder = JSONDecoder()
        if let items = try? decoder.decode([RadialAction].self, from: data) { return items }
        if let legacy = try? decoder.decode([RadialCategory].self, from: data) {
            return legacy.map { $0.asAction }
        }
        return nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Reset to defaults.
    func resetToDefaults() {
        items = Self.defaultItems
    }

    /// Access an item by index path.
    func actionAt(path: [Int]) -> RadialAction? {
        guard let idx = path.first, idx < items.count else { return nil }
        return Self.item(at: Array(path.dropFirst()), in: items[idx])
    }

    private static func item(at path: [Int], in parent: RadialAction) -> RadialAction? {
        guard let idx = path.first else { return parent }
        let children = parent.children ?? []
        guard idx < children.count else { return nil }
        return item(at: Array(path.dropFirst()), in: children[idx])
    }

    /// Run `body` on the child list that `parentPath` addresses.
    @discardableResult
    private func withChildren<T>(of parentPath: [Int], _ body: (inout [RadialAction]) -> T) -> T? {
        Self.mutate(&items, path: parentPath, body)
    }

    private static func mutate<T>(_ list: inout [RadialAction], path: [Int],
                                  _ body: (inout [RadialAction]) -> T) -> T? {
        guard let idx = path.first else { return body(&list) }
        guard idx < list.count else { return nil }
        var children = list[idx].children ?? []
        let result = mutate(&children, path: Array(path.dropFirst()), body)
        if result != nil { list[idx].children = children }
        return result
    }

    /// Replace the item at path.
    func setAction(_ action: RadialAction, at path: [Int]) {
        guard let index = path.last else { return }
        withChildren(of: Array(path.dropLast())) { siblings in
            guard index < siblings.count else { return }
            siblings[index] = action
        }
    }

    /// Remove the item at path.
    func removeAction(at path: [Int]) {
        guard let index = path.last else { return }
        withChildren(of: Array(path.dropLast())) { siblings in
            guard index < siblings.count else { return }
            siblings.remove(at: index)
        }
    }

    /// Insert a copy of the item at `path` directly below it, and return the
    /// new item's path so the caller can open or reveal it.
    @discardableResult
    func duplicateAction(at path: [Int]) -> [Int]? {
        guard let index = path.last,
              let action = actionAt(path: path) else { return nil }
        let parentPath = Array(path.dropLast())
        insertAction(action.duplicated(), at: parentPath, index: index + 1)
        return parentPath + [index + 1]
    }

    /// Append an item to the ring addressed by `parentPath` (`[]` = first ring).
    func appendAction(_ action: RadialAction, at parentPath: [Int]) {
        insertAction(action, at: parentPath, index: nil)
    }

    /// Insert an item into the ring addressed by `parentPath` (`[]` = first ring).
    /// A plain action gains an empty child list, becoming a subcategory.
    func insertAction(_ action: RadialAction, at parentPath: [Int], index: Int?) {
        withChildren(of: parentPath) { siblings in
            let target = min(max(index ?? siblings.count, 0), siblings.count)
            siblings.insert(action, at: target)
        }
    }

    /// Move an action or subcategory to another parent category/subcategory.
    @discardableResult
    func moveAction(from sourcePath: [Int], toParentPath destinationParentPath: [Int], insertionIndex: Int? = nil) -> Bool {
        guard canMoveAction(from: sourcePath, toParentPath: destinationParentPath),
              let action = actionAt(path: sourcePath) else { return false }

        let sourceParent = Array(sourcePath.dropLast())
        let sourceIndex = sourcePath[sourcePath.count - 1]
        let adjustedDestination = adjustedParentPath(destinationParentPath, afterRemoving: sourcePath)
        let adjustedIndex: Int?
        if sourceParent == destinationParentPath, let insertionIndex {
            let target = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
            if target == sourceIndex { return false }
            adjustedIndex = target
        } else {
            adjustedIndex = insertionIndex
        }

        removeAction(at: sourcePath)
        insertAction(action, at: adjustedDestination, index: adjustedIndex)
        return true
    }

    func canMoveAction(from sourcePath: [Int], toParentPath destinationParentPath: [Int]) -> Bool {
        !sourcePath.isEmpty &&
        !destinationParentPath.starts(with: sourcePath) &&
        canAppendAction(to: destinationParentPath) &&
        actionAt(path: sourcePath) != nil
    }

    private func canAppendAction(to parentPath: [Int]) -> Bool {
        guard !parentPath.isEmpty else { return true }
        return actionAt(path: parentPath)?.isSubcategory == true
    }

    private func adjustedParentPath(_ parentPath: [Int], afterRemoving sourcePath: [Int]) -> [Int] {
        let sourceParent = Array(sourcePath.dropLast())
        let sourceIndex = sourcePath[sourcePath.count - 1]
        guard parentPath.count > sourceParent.count,
              Array(parentPath.prefix(sourceParent.count)) == sourceParent,
              parentPath[sourceParent.count] > sourceIndex else { return parentPath }

        var adjusted = parentPath
        adjusted[sourceParent.count] -= 1
        return adjusted
    }

    /// Move an item within its sibling list at the given parent path.
    func moveAction(atParentPath parentPath: [Int], from: Int, to: Int) {
        withChildren(of: parentPath) { siblings in
            guard from < siblings.count, to <= siblings.count else { return }
            let item = siblings.remove(at: from)
            siblings.insert(item, at: min(to, siblings.count))
        }
    }

    // MARK: - Default menu

    /// Built-in Global Menu, authored as categories and flattened into items.
    static var defaultItems: [RadialAction] { defaultCategories.map { $0.asAction } }

    private static let defaultCategories: [RadialCategory] = [
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
