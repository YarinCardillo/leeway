import Darwin
import Foundation

/// The account book on disk. Changes run under an advisory lock, so Leeway.app, the CLI and other apps
/// can edit at the same time without losing each other's changes.
///
/// The lock is an `flock` on a private file beside the book, like the poll lock, but it is held only for
/// the length of one change and callers wait for it.
public struct AccountBookFile: Sendable {
    private let url: URL

    /// - Parameter url: The book file, usually `AccountBook.fileURL(home:)`.
    public init(url: URL) { self.url = url }

    /// Reads the book without locking: writes replace the file atomically, so a read is always whole.
    public func load() throws -> AccountBook { try AccountBook.load(url) }

    /// A value that differs between two calls when the book file was replaced in between, empty while there is
    /// no file. Writes replace the file, so its identity changes with every saved change.
    public func changeMarker() -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "" }
        let identity = (attributes[.systemFileNumber] as? NSNumber)?.stringValue ?? ""
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(identity)-\(modified)-\(attributes[.size] as? NSNumber ?? 0)"
    }

    /// Runs one change on the latest book and saves it when it changed. Returns what the change returns.
    public func update<Result>(_ change: (inout AccountBook) throws -> Result) throws -> Result {
        let lockFile = url.deletingLastPathComponent().appendingPathComponent("accounts.lock")
        try PrivateStorage.file(lockFile, create: true)
        let descriptor = open(lockFile.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw CoreError.storage
        }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        let original = try AccountBook.load(url)
        var book = original
        let result = try change(&book)
        if book != original { try book.save(to: url) }
        return result
    }
}
