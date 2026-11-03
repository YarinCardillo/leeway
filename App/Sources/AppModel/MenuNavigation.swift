public enum MenuFocus: Hashable, Sendable {
    case account(String), automatic, refresh, settings, quit
}

/// Defines the keyboard order of enabled menu actions.
public enum MenuNavigation {
    public static func actions(accountIDs: [String], canRefresh: Bool) -> [MenuFocus] {
        accountIDs.map(MenuFocus.account) + (accountIDs.isEmpty ? [] : [.automatic])
            + (canRefresh ? [.refresh] : []) + [.settings, .quit]
    }

    public static func move(from current: MenuFocus?, forward: Bool, in actions: [MenuFocus]) -> MenuFocus? {
        guard !actions.isEmpty else { return nil }
        guard let current, let index = actions.firstIndex(of: current) else { return forward ? actions.first : actions.last }
        return actions[min(max(index + (forward ? 1 : -1), 0), actions.count - 1)]
    }
}
