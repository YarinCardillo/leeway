import Foundation

/// Holds in-progress text without changing the saved account name.
public struct AccountNameDraft {
    public private(set) var text: String
    public private(set) var isEditing = false
    private var savedName: String
    public init(_ text: String) { self.text = text; savedName = text }
    public mutating func update(_ text: String) { self.text = text; isEditing = true }
    /// Ends editing, returning a valid committed name or reverting the draft on cancellation.
    public mutating func finishEditing(commit: Bool) -> String? {
        let name = commit && isEditing ? acceptedName : nil
        if let name { savedName = name }
        text = savedName
        isEditing = false
        return name
    }

    public var acceptedName: String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
