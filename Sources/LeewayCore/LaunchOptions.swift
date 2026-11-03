import Foundation

public struct LaunchOptions: Sendable {
    public let home: URL
    public let policyFile: URL
    public let arguments: [String]
    /// Resolves global path options while retaining the command and its arguments.
    public static func parse(_ arguments: [String], defaultHome: URL) throws -> LaunchOptions {
        var homeText: String?, policyText: String?, command: [String] = [], index = 0
        while index < arguments.count {
            let key = arguments[index]
            if key != "--home", key != "--policy" { command.append(key); index += 1; continue }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw CoreError.invalidRequest("missing value for \(key)")
            }
            let value = arguments[index + 1]
            guard !value.isEmpty else { throw CoreError.invalidRequest("empty value for \(key)") }
            if key == "--home" {
                guard homeText == nil else { throw CoreError.invalidRequest("duplicate --home") }
                homeText = value
            } else {
                guard policyText == nil else { throw CoreError.invalidRequest("duplicate --policy") }
                policyText = value
            }
            index += 2
        }
        let home = homeText.map { expand($0, home: defaultHome) } ?? defaultHome
        return LaunchOptions(home: home, policyFile: policyText.map { expand($0, home: home) }
            ?? home.appendingPathComponent(".config/leeway/policy.toml"), arguments: command)
    }
}
