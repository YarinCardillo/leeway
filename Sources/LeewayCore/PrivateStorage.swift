import Darwin
import Foundation

/// Owner-only storage shared by the CLI and app. Failures never expose local paths.
public enum PrivateStorage {
    /// Creates missing parents privately and tightens the requested existing directory only.
    public static func directory(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) { try directory(parent) }
        guard mkdir(url.path, 0o700) == 0 || (errno == EEXIST && isDirectory(url)) else { throw CoreError.storage }
        guard chmod(url.path, 0o700) == 0 else { throw CoreError.storage }
    }

    /// Protects a regular file, optionally creating it with private permissions from the start.
    public static func file(_ url: URL, create: Bool = false) throws {
        let parent = url.deletingLastPathComponent()
        // Existing custom policy/database parents may be shared with unrelated applications.
        if parent.lastPathComponent == "leeway" || !FileManager.default.fileExists(atPath: parent.path) {
            try directory(parent)
        }
        let descriptor = open(url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW | (create ? O_CREAT : 0), 0o600)
        guard descriptor >= 0 else { throw CoreError.storage }
        defer { close(descriptor) }
        guard fchmod(descriptor, 0o600) == 0 else { throw CoreError.storage }
    }

    /// Replaces a file atomically using a private temporary file in its own directory.
    public static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".leeway-" + UUID().uuidString)
        try file(temporary, create: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        guard rename(temporary.path, url.path) == 0 else { throw CoreError.storage }
    }

    static func database(_ path: String) throws {
        guard path != ":memory:" else { return }
        try file(URL(fileURLWithPath: path), create: true)
        for suffix in ["-journal", "-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
            try file(URL(fileURLWithPath: path + suffix))
        }
    }
}
