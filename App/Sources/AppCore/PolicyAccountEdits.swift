import AppModel
import LeewayCore

/// Three-way merging prevents unrelated settings edits from replacing newer policy values.
enum PolicyAccountEdits {
    enum Conflict: Error { case externalChange }

    static func merge<T: Equatable>(_ desired: T, baseline: T?, current: T) throws -> T {
        guard let baseline else { return desired }
        guard desired != baseline else { return current }
        guard current == baseline || current == desired else { throw Conflict.externalChange }
        return desired
    }

    static func apply(_ choice: AccountPreference, baseline: AccountPreference?,
                      to account: AccountConfiguration) throws -> AccountConfiguration {
        let target = try mergeTarget(choice, baseline: baseline, current: account)
        return try AccountConfiguration(id: account.id, provider: account.provider,
            label: merge(choice.name ?? account.label, baseline: baseline?.name, current: account.label),
            configDir: account.configDir,
            isEnabled: merge(choice.isEnabled, baseline: baseline?.isEnabled, current: account.isEnabled),
            targetLow: target.low, targetHigh: target.high,
            reserveAccount: merge(choice.reserveID, baseline: baseline.map(\.reserveID), current: account.reserveAccount),
            overTarget: account.overTarget)
    }

    private static func mergeTarget(_ desired: AccountPreference, baseline: AccountPreference?,
                                    current: AccountConfiguration) throws -> (low: Double, high: Double) {
        let choice = [desired.targetLow, desired.targetHigh]
        let original = baseline.map { [$0.targetLow, $0.targetHigh] }
        let result = try merge(choice, baseline: original, current: [current.targetLow, current.targetHigh])
        return (result[0], result[1])
    }

    static func aliasChoice(_ desired: AccountPreference, baseline: AccountPreference?,
                            alias: AccountPreference) -> AccountPreference {
        var result = alias
        if baseline?.isEnabled != desired.isEnabled { result.isEnabled = desired.isEnabled }
        if baseline?.targetLow != desired.targetLow || baseline?.targetHigh != desired.targetHigh {
            result.targetLow = desired.targetLow
            result.targetHigh = desired.targetHigh
        }
        if baseline?.reserveID != desired.reserveID { result.reserveID = desired.reserveID }
        return result
    }
}
