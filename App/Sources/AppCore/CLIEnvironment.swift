import Foundation

/// Adds standard native-installer and Homebrew locations when Finder supplies a minimal PATH.
public enum CLIEnvironment {
    public static func forApplication(home: URL, inherited: [String: String]) -> [String: String] {
        var result = inherited
        var paths = (inherited["PATH"] ?? "").components(separatedBy: ":").filter { !$0.isEmpty }
        let locations = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for location in locations where !paths.contains(location) { paths.append(location) }
        result["PATH"] = paths.joined(separator: ":")
        return result
    }
}
