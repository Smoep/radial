import Foundation
import AppKit

/// Metadata for one app-specific radial menu. The menu contents live in their
/// own `RadialMenuStore`, keyed by bundle identifier.
struct AppMenuRef: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    var appPath: String?

    var id: String { bundleID }
}

/// A full app menu (metadata + contents) used for backup/restore.
struct AppMenuSnapshot: Codable {
    var bundleID: String
    var name: String
    var appPath: String?
    var items: [RadialAction]

    private enum CodingKeys: String, CodingKey {
        case bundleID, name, appPath, items, categories
    }

    init(bundleID: String, name: String, appPath: String?, items: [RadialAction]) {
        self.bundleID = bundleID
        self.name = name
        self.appPath = appPath
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decode(String.self, forKey: .name)
        appPath = try c.decodeIfPresent(String.self, forKey: .appPath)
        if let items = try c.decodeIfPresent([RadialAction].self, forKey: .items) {
            self.items = items
        } else {
            // Schema 2 backups stored the legacy category shape.
            let legacy = try c.decodeIfPresent([RadialCategory].self, forKey: .categories) ?? []
            items = legacy.map { $0.asAction }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(appPath, forKey: .appPath)
        try c.encode(items, forKey: .items)
    }
}

/// Registry of app-specific radial menus.
///
/// The index (which apps have a menu) is stored under `radialAppMenuIndex`;
/// each menu's categories live under `radialAppMenu.<bundleID>` so a single
/// large blob is never rewritten on every keystroke in the editor.
@Observable
final class AppMenuLibrary {

    static let shared = AppMenuLibrary()

    private let indexKey = "radialAppMenuIndex"

    var apps: [AppMenuRef] = [] {
        didSet { saveIndex() }
    }

    @ObservationIgnored private var stores: [String: RadialMenuStore] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: indexKey),
           let decoded = try? JSONDecoder().decode([AppMenuRef].self, from: data) {
            apps = decoded
        }
    }

    static func storageKey(for bundleID: String) -> String { "radialAppMenu.\(bundleID)" }

    func hasMenu(for bundleID: String) -> Bool {
        apps.contains { $0.bundleID == bundleID }
    }

    func ref(for bundleID: String) -> AppMenuRef? {
        apps.first { $0.bundleID == bundleID }
    }

    /// The store backing a registered app menu, or nil when the app has none.
    func store(for bundleID: String) -> RadialMenuStore? {
        guard hasMenu(for: bundleID) else { return nil }
        if let existing = stores[bundleID] { return existing }
        let store = RadialMenuStore(storageKey: Self.storageKey(for: bundleID), seedDefaults: false)
        stores[bundleID] = store
        return store
    }

    /// Register a new (empty) app menu. Returns its store.
    @discardableResult
    func addMenu(bundleID: String, name: String, appPath: String?) -> RadialMenuStore? {
        guard !bundleID.isEmpty else { return nil }
        if !hasMenu(for: bundleID) {
            var updated = apps
            updated.append(AppMenuRef(bundleID: bundleID, name: name, appPath: appPath))
            updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            apps = updated
        }
        return store(for: bundleID)
    }

    func removeMenu(bundleID: String) {
        stores.removeValue(forKey: bundleID)
        UserDefaults.standard.removeObject(forKey: Self.storageKey(for: bundleID))
        apps.removeAll { $0.bundleID == bundleID }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }
    }

    /// Items to render for a bundle identifier, or nil when there is no usable
    /// app menu. An empty app menu counts as "none" so the user never sees an
    /// empty ring.
    func items(for bundleID: String?) -> [RadialAction]? {
        guard let bundleID,
              let store = store(for: bundleID),
              !store.items.isEmpty else { return nil }
        return store.items
    }

    // MARK: - Backup support

    func snapshot() -> [AppMenuSnapshot] {
        apps.map { ref in
            AppMenuSnapshot(bundleID: ref.bundleID,
                            name: ref.name,
                            appPath: ref.appPath,
                            items: store(for: ref.bundleID)?.items ?? [])
        }
    }

    func replaceAll(with snapshots: [AppMenuSnapshot]) {
        for ref in apps {
            stores.removeValue(forKey: ref.bundleID)
            UserDefaults.standard.removeObject(forKey: Self.storageKey(for: ref.bundleID))
        }
        apps = snapshots.map {
            AppMenuRef(bundleID: $0.bundleID, name: $0.name, appPath: $0.appPath)
        }
        for snapshot in snapshots {
            store(for: snapshot.bundleID)?.items = snapshot.items
        }
    }

    // MARK: - Running applications

    /// Regular (Dock-visible) running apps that don't already have a menu,
    /// excluding Radial itself.
    func selectableRunningApps() -> [AppMenuRef] {
        let ownBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppMenuRef? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != ownBundleID,
                      !hasMenu(for: bundleID) else { return nil }
                return AppMenuRef(bundleID: bundleID,
                                  name: Self.displayName(for: app) ?? bundleID,
                                  appPath: app.bundleURL?.path)
            }
            .reduce(into: [AppMenuRef]()) { result, ref in
                if !result.contains(where: { $0.bundleID == ref.bundleID }) { result.append(ref) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name users recognise from Finder, which can differ from the process
    /// name: Visual Studio Code reports `localizedName` as just "Code".
    private static func displayName(for app: NSRunningApplication) -> String? {
        if let url = app.bundleURL {
            let fileName = url.deletingPathExtension().lastPathComponent
            if !fileName.isEmpty { return fileName }
        }
        return app.localizedName
    }
}
