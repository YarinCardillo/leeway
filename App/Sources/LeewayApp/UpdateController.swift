import AppModel
import Foundation
import Observation
import Sparkle

/// Sparkle is started only when release feed metadata has been supplied by the release build.
@Observable @MainActor
final class UpdateController: NSObject {
    private(set) var isConfigured = false
    private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private(set) var checkResult: UpdateCheckResult?

    override init() {
        super.init()
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        isConfigured = true
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in self?.canCheck = self?.controller?.updater.canCheckForUpdates ?? false }
        }
    }

    func configure(_ preferences: AppPreferences) {
        controller?.updater.automaticallyChecksForUpdates = preferences.updatesAutomatically
        controller?.updater.automaticallyDownloadsUpdates = preferences.updatesAutomatically
    }

    func start(_ preferences: AppPreferences) {
        configure(preferences)
        controller?.startUpdater()
    }

    func checkNow() {
        checkResult = UpdateCheckResult.request(isConfigured: isConfigured, canCheck: canCheck) {
            controller?.checkForUpdates(nil)
        }
    }
}
