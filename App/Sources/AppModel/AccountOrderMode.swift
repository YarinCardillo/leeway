import Foundation

/// Menu row ordering is independent of the account selected for the status item.
public enum AccountOrderMode: String, Codable, Sendable, CaseIterable {
    case manual
    case mostAtRisk

    func ordered(_ accounts: [AccountUsage], manualIDs: [String]) -> [AccountUsage] {
        if self == .mostAtRisk { return accounts.sorted(by: Self.higherRisk) }
        return accounts.sorted {
            let left = manualIDs.firstIndex(of: $0.id) ?? Int.max
            let right = manualIDs.firstIndex(of: $1.id) ?? Int.max
            if left != right { return left < right }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    static func higherRisk(_ left: AccountUsage, _ right: AccountUsage) -> Bool {
        if left.priority != right.priority { return left.priority > right.priority }
        if left.upperForecast != right.upperForecast { return (left.upperForecast ?? -1) > (right.upperForecast ?? -1) }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
}
