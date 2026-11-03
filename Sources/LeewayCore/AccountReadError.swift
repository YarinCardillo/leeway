/// Safe source failure categories. Never carries process output or authentication details.
public enum AccountReadError: String, Codable, Error, Sendable, CaseIterable {
    case cliMissing = "cli_missing"
    case timeout
    case notSignedIn = "not_signed_in"
    case invalidOutput = "invalid_output"
}
