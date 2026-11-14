import Observation
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private final class MainAppLoginItem: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
@Observable
final class LaunchAtLoginController {
    private let service: LoginItemManaging
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?

    init(service: LoginItemManaging? = nil) {
        self.service = service ?? MainAppLoginItem()
        refresh()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var statusText: String {
        switch status {
        case .enabled: "Enabled"
        case .notRegistered: "Off"
        case .requiresApproval: "Approval is required in System Settings → Login Items."
        case .notFound: "Unavailable for this build. Use an installed, signed copy of Klip."
        @unknown default: "Check Login Items in System Settings."
        }
    }

    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled { try service.register() }
            else if status != .notRegistered { try service.unregister() }
        } catch {
            errorMessage = "Couldn’t change launch at login. \(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
