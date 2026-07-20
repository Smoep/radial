import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Backup Payload

/// Serializable snapshot of every user-configurable setting. All fields are
/// optional so that older or newer backup files decode leniently — only the
/// values present are applied on import.
struct SettingsData: Codable {
    var activationHoldDuration: Double?
    var gridDivisions: Int?
    var dragRange: Double?
    var ringDelay: Double?
    var liftToSelect: Bool?
    var isTestMode: Bool?
    var activationMargin: Double?
    var ringHeight: Double?
    var selectionWidth: Double?
    var menuLabelFontSize: Double?
    var menuLabelWrappingEnabled: Bool?
    var categoryFlexibilityPercent: Double?
    var pauseWhileTyping: Bool?
    var activationTrigger: String?
    var overlayOpacity: Double?
    var hotkeyEnabled: Bool?
    var hotkeyKeyCode: Int?
    var hotkeyModifiers: Int?
    var hotkeyKeyLabel: String?
    var hotkeyMode: String?
    var doubleTapWindow: Double?
    var trackpadEnabled: Bool?
    var mouseEnabled: Bool?
    var mouseButton: String?
    var mouseHoldDuration: Double?
    var mouseReleaseToSelect: Bool?
}

/// Top-level backup document written to / read from disk.
struct RadialBackup: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String?
    var categories: [RadialCategory]
    var settings: SettingsData
}

// MARK: - AppSettings snapshot / apply

extension AppSettings {
    /// Capture the current settings into a serializable snapshot.
    var backupSnapshot: SettingsData {
        SettingsData(
            activationHoldDuration: activationHoldDuration,
            gridDivisions: gridDivisions,
            dragRange: dragRange,
            ringDelay: ringDelay,
            liftToSelect: liftToSelect,
            isTestMode: isTestMode,
            activationMargin: activationMargin,
            ringHeight: ringHeight,
            selectionWidth: selectionWidth,
            menuLabelFontSize: menuLabelFontSize,
            menuLabelWrappingEnabled: menuLabelWrappingEnabled,
            categoryFlexibilityPercent: categoryFlexibilityPercent,
            pauseWhileTyping: pauseWhileTyping,
            activationTrigger: activationTrigger.rawValue,
            overlayOpacity: overlayOpacity,
            hotkeyEnabled: hotkeyEnabled,
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers,
            hotkeyKeyLabel: hotkeyKeyLabel,
            hotkeyMode: hotkeyMode.rawValue,
            doubleTapWindow: doubleTapWindow,
            trackpadEnabled: trackpadEnabled,
            mouseEnabled: mouseEnabled,
            mouseButton: mouseButton.rawValue,
            mouseHoldDuration: mouseHoldDuration,
            mouseReleaseToSelect: mouseReleaseToSelect
        )
    }

    /// Apply a decoded snapshot, ignoring any missing (nil) fields. Values are
    /// clamped to the same ranges used when loading from UserDefaults.
    func apply(_ d: SettingsData) {
        if let v = d.activationHoldDuration { activationHoldDuration = v }
        if let v = d.gridDivisions { gridDivisions = v }
        if let v = d.dragRange { dragRange = v }
        if let v = d.ringDelay { ringDelay = v }
        if let v = d.liftToSelect { liftToSelect = v }
        if let v = d.isTestMode { isTestMode = v }
        if let v = d.activationMargin { activationMargin = v }
        if let v = d.ringHeight { ringHeight = v }
        if let v = d.selectionWidth { selectionWidth = v }
        if let v = d.menuLabelFontSize { menuLabelFontSize = min(max(v, 8), 18) }
        if let v = d.menuLabelWrappingEnabled { menuLabelWrappingEnabled = v }
        if let v = d.categoryFlexibilityPercent { categoryFlexibilityPercent = min(max(v, 0), 50) }
        if let v = d.pauseWhileTyping { pauseWhileTyping = v }
        if let v = d.activationTrigger, let t = ActivationTrigger(rawValue: v) { activationTrigger = t }
        if let v = d.overlayOpacity { overlayOpacity = v }
        if let v = d.hotkeyEnabled { hotkeyEnabled = v }
        if let v = d.hotkeyKeyCode { hotkeyKeyCode = v }
        if let v = d.hotkeyModifiers { hotkeyModifiers = v }
        if let v = d.hotkeyKeyLabel { hotkeyKeyLabel = v }
        if let v = d.hotkeyMode, let m = HotkeyMode(rawValue: v) { hotkeyMode = m }
        if let v = d.doubleTapWindow { doubleTapWindow = v }
        if let v = d.trackpadEnabled { trackpadEnabled = v }
        if let v = d.mouseEnabled { mouseEnabled = v }
        if let v = d.mouseButton, let b = MouseButton(rawValue: v) { mouseButton = b }
        if let v = d.mouseHoldDuration { mouseHoldDuration = v }
        if let v = d.mouseReleaseToSelect { mouseReleaseToSelect = v }
        flush()
    }
}

// MARK: - Backup Service

enum ConfigBackup {
    static let currentSchemaVersion = 1

    /// Build a backup document from the live store and settings.
    static func makeBackup() -> RadialBackup {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return RadialBackup(
            schemaVersion: currentSchemaVersion,
            exportedAt: Date(),
            appVersion: appVersion,
            categories: RadialMenuStore.shared.categories,
            settings: AppSettings.shared.backupSnapshot
        )
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static func defaultFileName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "Radial-Backup-\(df.string(from: Date())).json"
    }

    // MARK: Export

    /// Present a save panel and write the current configuration to disk.
    @MainActor
    static func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "Export Radial Configuration"
        panel.nameFieldStringValue = defaultFileName()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try encoder().encode(makeBackup())
            try data.write(to: url, options: .atomic)
        } catch {
            presentAlert(style: .warning,
                         title: "Export Failed",
                         message: error.localizedDescription)
        }
    }

    // MARK: Import

    /// Present an open panel, decode the selected backup, confirm, then apply.
    @MainActor
    static func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Radial Configuration"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let backup: RadialBackup
        do {
            let data = try Data(contentsOf: url)
            backup = try decoder().decode(RadialBackup.self, from: data)
        } catch {
            presentAlert(style: .warning,
                         title: "Import Failed",
                         message: "The selected file is not a valid Radial backup.\n\n\(error.localizedDescription)")
            return
        }

        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Replace current configuration?"
        confirm.informativeText = "This will overwrite your menu (\(backup.categories.count) categories) and all settings with the contents of this backup. This cannot be undone."
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        apply(backup)

        presentAlert(style: .informational,
                     title: "Import Complete",
                     message: "Restored \(backup.categories.count) categories and your settings.")
    }

    /// Apply a decoded backup to the live store and settings.
    static func apply(_ backup: RadialBackup) {
        RadialMenuStore.shared.categories = backup.categories
        AppSettings.shared.apply(backup.settings)
    }

    @MainActor
    private static func presentAlert(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
