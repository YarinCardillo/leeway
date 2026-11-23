import LeewayCore

/// The product name an account row shows for its provider, and back.
extension Provider {
    var sourceName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok Bot"
        }
    }

    init(sourceName: String) {
        self = [Provider.codex, .grok].first { $0.sourceName == sourceName } ?? .claude
    }
}
