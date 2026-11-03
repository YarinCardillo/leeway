import Foundation

/// Readable defaults derived from configuration paths, never credential contents.
public enum AccountLabel {
    /// Returns a provider name with short folder context outside its standard home.
    public static func defaultName(provider: Provider, directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let name = provider == .claude ? "Claude" : "Codex"
        if directory.standardizedFileURL == home.appendingPathComponent(".\(provider.rawValue)").standardizedFileURL { return name }
        if directory.path.contains("/orca/claude-profiles/"), directory.lastPathComponent == "home" {
            return "\(name) (Orca profile)"
        }
        let folder = directory.lastPathComponent == ".\(provider.rawValue)" ? directory.deletingLastPathComponent().lastPathComponent : directory.lastPathComponent
        let context = folder.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !context.isEmpty, !context.contains("@") else { return "\(name) (custom folder)" }
        return "\(name) (\(context.prefix(24)))"
    }
}
