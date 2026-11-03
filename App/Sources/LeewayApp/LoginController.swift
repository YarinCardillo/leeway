import Observation
import ServiceManagement

@Observable @MainActor
final class LoginController {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval
    private(set) var hasError = false

    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            hasError = false
        } catch { hasError = true }
        reload()
    }

    func reload() {
        isEnabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
