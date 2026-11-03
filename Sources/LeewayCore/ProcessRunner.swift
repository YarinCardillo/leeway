import Foundation

public struct ProcessRequest: Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL
    public let timeout: TimeInterval
    public let isCancelled: @Sendable () -> Bool

    public init(executable: String, arguments: [String], environment: [String: String], workingDirectory: URL,
                timeout: TimeInterval = 90, isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
        self.workingDirectory = workingDirectory; self.timeout = timeout
        self.isCancelled = isCancelled
    }
}

public struct ProcessOutput: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public init(exitCode: Int32, stdout: String) { self.exitCode = exitCode; self.stdout = stdout }
}

public protocol ProcessRunner: Sendable {
    func run(_ request: ProcessRequest) throws -> ProcessOutput
}
