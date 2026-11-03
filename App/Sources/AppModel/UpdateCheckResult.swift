/// An update request reports missing configuration rather than silently doing nothing.
public enum UpdateCheckResult: Equatable, Sendable {
    case notConfigured, busy, started

    public static func request(isConfigured: Bool, canCheck: Bool, perform: () -> Void) -> UpdateCheckResult {
        guard isConfigured else { return .notConfigured }
        guard canCheck else { return .busy }
        perform()
        return .started
    }
}
