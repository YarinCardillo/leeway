import AppCore
import AppKit
import Foundation
import XCTest

@MainActor
final class ProbeShutdownTests: XCTestCase {
    func testFinding10_AppTerminationStopsTheLiveProviderProbe() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let script = home.appendingPathComponent("claude"), file = home.appendingPathComponent("pid")
        try "#!/bin/sh\nif [ \"$1\" = auth ]; then printf '{}'; exit; fi\ntrap '' TERM\nprintf '%s' \"$$\" > \"$PROBE_PID\"\nsleep 30\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let provider = try CoreUsageProvider.live(home: home,
            environment: ["PATH": home.path + ":/usr/bin:/bin", "PROBE_PID": file.path])
        let refresh = Task { try await provider.refresh() }
        for _ in 0..<300 where !FileManager.default.fileExists(atPath: file.path) { try await Task.sleep(for: .milliseconds(10)) }
        let pid = try XCTUnwrap(Int32(String(contentsOf: file, encoding: .utf8)))
        defer { kill(-pid, SIGKILL) }
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        for _ in 0..<150 {
            if kill(pid, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(kill(pid, 0), -1)
        kill(-pid, SIGKILL)
        _ = try? await refresh.value
    }
}
