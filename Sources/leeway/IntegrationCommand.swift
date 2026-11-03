import Foundation

/// Dispatches optional agent integrations without loading quota or credential data.
enum IntegrationCommand {
    /// Returns nil for another CLI command, otherwise the integration process exit status.
    static func run(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Int32? {
        guard arguments.first == "integrations" else { return nil }
        let process = Process()
        process.executableURL = try runtime(environment: environment)
        process.arguments = Array(arguments.dropFirst())
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do { try process.run() }
        catch { throw IntegrationCommandError.launchFailed }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func runtime(environment: [String: String]) throws -> URL {
        if let override = environment["LEEWAY_INTEGRATIONS_EXECUTABLE"] {
            let url = URL(fileURLWithPath: override)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw IntegrationCommandError.runtimeMissing
            }
            return url
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var directory = executable.deletingLastPathComponent()
        var candidates = [directory.appendingPathComponent("../share/leeway/integrations/leeway-integrations")]
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("integrations/leeway-integrations"))
        }
        for _ in 0..<6 {
            candidates.append(directory.appendingPathComponent("integrations/leeway-integrations"))
            directory.deleteLastPathComponent()
        }
        guard let result = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw IntegrationCommandError.runtimeMissing
        }
        return result
    }
}

enum IntegrationCommandError: Error, CustomStringConvertible {
    case runtimeMissing
    case launchFailed

    var description: String {
        switch self {
        case .runtimeMissing: "Integration runtime missing. Install the Leeway integration resources."
        case .launchFailed: "Could not start the integration runtime. Check that Python 3.10 or newer is available."
        }
    }
}
