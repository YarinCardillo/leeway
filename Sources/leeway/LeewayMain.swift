import Foundation
import Darwin
import LeewayCore

@main
struct LeewayMain {
    /// How often a polling `serve` looks for refreshes that another process left in the store.
    private static let requestCheckSeconds: TimeInterval = 5
    /// Exit code of a leeway that is older than the store it was asked to read.
    private static let olderThanStoreExitCode: Int32 = 3
    /// Printed on stdout, like every other JSON answer, so callers parse one stream.
    private static let olderThanStoreDocument = "{\"schema_version\":1,\"error\":\"\(CoreError.storeNewerThanBinary.description)\"}"

    static func main() async {
        do { try await run() }
        catch CoreError.storeNewerThanBinary {
            print(olderThanStoreDocument)
            exit(olderThanStoreExitCode)
        } catch {
            let message = (error as? CoreError)?.description ?? (error as? PolicyError)?.description ?? (error as? IntegrationCommandError)?.description ?? "Could not complete the command. Check file access and try again."
            FileHandle.standardError.write(Data(("leeway: " + message + "\n").utf8))
            exit(1)
        }
    }

    private static func run() async throws {
        let options = try LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()),
            defaultHome: FileManager.default.homeDirectoryForCurrentUser)
        if let code = try IntegrationCommand.run(arguments: options.arguments) { exit(code) }
        if options.arguments.isEmpty || ["help", "--help", "-h"].contains(options.arguments[0]) {
            print(LeewayCLI.help)
            return
        }
        if options.arguments.first == "version" {
            print(try LeewayCLI.runVersion(Array(options.arguments.dropFirst())))
            return
        }
        if let status = try IntegrationCommand.run(arguments: options.arguments) { exit(status) }
        let policy = try Policy.load(options.policyFile, home: options.home)
        let runner = SystemProcessRunner()
        defer { runner.shutdown() }
        let service = try makeService(options, policy: policy, runner: runner)
        if options.arguments == ["serve"] { try await serve(service, policy: policy, options: options, runner: runner) }
        else {
            let accounts = AccountsCommand(home: options.home, policy: policy, environment: ProcessInfo.processInfo.environment)
            print(try await LeewayCLI(provider: service, accounts: accounts).run(options.arguments))
        }
    }

    private static func serve(_ service: UsageService, policy: Policy, options: LaunchOptions, runner: SystemProcessRunner) async throws {
        let changes = try PolicyChanges.watch(file: options.policyFile, home: options.home)
        let signals = ShutdownSignals()
        let server = try LoopbackServer(provider: service, port: UInt16(policy.port))
        server.start()
        defer { server.stop() }
        FileHandle.standardError.write(Data("Leeway listening on http://127.0.0.1:\(server.port)\n".utf8))
        let polling = Task {
            await PollingLoop.run(provider: service, minutes: policy.pollMinutes,
                changes: changes, requestCheckSeconds: requestCheckSeconds)
        }
        await signals.wait()
        server.stop()
        polling.cancel()
        runner.shutdown()
        await polling.value
    }

    private static func makeService(_ options: LaunchOptions, policy: Policy, runner: SystemProcessRunner) throws -> UsageService {
        let directory = options.home.appendingPathComponent("Library/Application Support/leeway")
        let store = try SnapshotStore(path: directory.appendingPathComponent("history.sqlite").path)
        return UsageService(home: options.home, policy: policy, store: store, runner: runner,
            environment: ProcessInfo.processInfo.environment, policyFile: options.policyFile,
            pollLock: PollLock(path: directory.appendingPathComponent("poll.lock").path))
    }
}
