import Foundation
import Observation
import ServiceManagement

/// Keeps the settings UI in sync with Radial's system-managed login item.
@MainActor
@Observable
final class LoginItemManager {
    static let shared = LoginItemManager()

    private(set) var isRegistered = false
    private(set) var requiresApproval = false
    private(set) var errorMessage: String?

    private init() {
        refresh()
    }

    func setRegistered(_ shouldRegister: Bool) {
        errorMessage = nil

        do {
            if shouldRegister {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh(preservingError: true)
    }

    func refresh(preservingError: Bool = false) {
        if !preservingError {
            errorMessage = nil
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            isRegistered = true
            requiresApproval = false
        case .requiresApproval:
            isRegistered = true
            requiresApproval = true
        case .notRegistered, .notFound:
            isRegistered = false
            requiresApproval = false
        @unknown default:
            isRegistered = false
            requiresApproval = false
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
