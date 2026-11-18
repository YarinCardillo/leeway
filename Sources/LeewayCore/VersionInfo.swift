import Foundation

/// The release version of this build. `App/Version.xcconfig` is the source of truth;
/// a test keeps the two equal.
public enum LeewayVersion {
    public static let current = "0.1.2"
}

/// What `leeway version --json` prints: enough for an app that bundles the helper to pick
/// the newer compatible copy between its own and an installed one.
public struct VersionInfo: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let statusSchema: Int
    public let accountsSchema: Int
    public let adviceSchema: Int
    public let storeSchema: Int

    /// The contract of this build.
    public static let current = VersionInfo(schemaVersion: 1, version: LeewayVersion.current,
        statusSchema: StatusDocument.currentSchemaVersion, accountsSchema: 1,
        adviceSchema: Advice.currentSchemaVersion, storeSchema: SnapshotStore.schemaVersion)
}
