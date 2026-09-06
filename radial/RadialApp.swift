import SwiftUI
import AppKit

extension Notification.Name {
    static let trackZoneToggleTracking = Notification.Name("trackZoneToggleTracking")
}

@main
struct RadialApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The visible settings window is managed by AppDelegate. Keeping this
        // empty scene satisfies SwiftUI without creating a normal app window.
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    /// Lazily created settings window — recreated if closed and deallocated.
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var trackingMenuItem: NSMenuItem?
    private var isTracking = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        configureStatusItem()
        // Start trackpad monitoring immediately — no need to open settings first.
        SessionEngine.shared.start()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button, let image = NSImage(named: "MenuBarIcon") {
            // The artwork occupies about 85% of its SVG canvas. A 21 pt image
            // produces an approximately 18 pt painted glyph in the menu bar.
            image.size = NSSize(width: 21, height: 21)
            image.isTemplate = true
            button.image = image
            button.imageScaling = .scaleNone
            button.imagePosition = .imageOnly
            button.toolTip = "Radial"
        }

        let menu = NSMenu()
        let trackingItem = NSMenuItem(
            title: "Pause Tracking", action: #selector(toggleTracking), keyEquivalent: ""
        )
        trackingItem.target = self
        menu.addItem(trackingItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Radial", action: #selector(quitApp), keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        trackingMenuItem = trackingItem
    }

    @objc private func toggleTracking() {
        isTracking.toggle()
        trackingMenuItem?.title = isTracking ? "Pause Tracking" : "Resume Tracking"
        NotificationCenter.default.post(name: .trackZoneToggleTracking, object: nil)
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func showSettings() {
        if settingsWindow == nil || !settingsWindow!.isVisible {
            let controller = NSHostingController(rootView: ContentView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Radial"
            window.setContentSize(NSSize(width: 820, height: 620))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.collectionBehavior = [.managed, .moveToActiveSpace]
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Restore collection behavior so window stops following the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.settingsWindow?.collectionBehavior = [.managed]
        }
    }
}
