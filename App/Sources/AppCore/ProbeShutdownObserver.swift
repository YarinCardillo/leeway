import AppKit
import Foundation
import LeewayCore

/// Covers Quit, keyboard termination and system-driven application termination.
final class ProbeShutdownObserver {
    private let runner: SystemProcessRunner
    private var token: NSObjectProtocol?

    init(runner: SystemProcessRunner) {
        self.runner = runner
        token = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: nil) { _ in runner.shutdown() }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
        runner.shutdown()
    }
}
