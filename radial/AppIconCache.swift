import AppKit

/// Loads and caches application icons by app path or name so the 60fps overlay
/// Canvas never hits the filesystem on every frame.
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    /// Returns the icon for an `appPath` that may be a full path
    /// (e.g. "/Applications/Safari.app") or a bare app name (e.g. "Safari").
    static func icon(forAppPath appPath: String) -> NSImage? {
        let key = appPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }

        guard let resolved = resolvedPath(for: key) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: resolved)
        cache[key] = image
        return image
    }

    /// Returns the Finder icon for any existing file or folder.
    static func icon(forFilePath path: String) -> NSImage? {
        let key = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }

        let expanded = (key as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: expanded)
        cache[key] = image
        return image
    }

    private static func resolvedPath(for appPath: String) -> String? {
        if appPath.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: appPath) ? appPath : nil
        }
        // Bare name: try the standard Applications locations, then Launch Services.
        let name = appPath.hasSuffix(".app") ? String(appPath.dropLast(4)) : appPath
        for base in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            let candidate = "\(base)/\(name).app"
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return NSWorkspace.shared.fullPath(forApplication: name)
    }
}
