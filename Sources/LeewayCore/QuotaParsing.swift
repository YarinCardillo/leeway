import Foundation
import CoreFoundation

func jsonObject(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func quotaNumber(_ raw: Any?) -> Double? {
    guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
    return value.doubleValue
}

func quotaDate(_ raw: Any?) -> Date? {
    // Accept Gregorian years 1 through 9999 so dates remain valid across API clients.
    let earliest: Double = -62_135_596_800, latest: Double = 253_402_300_799
    guard let seconds = quotaNumber(raw), (earliest...latest).contains(seconds) else { return nil }
    return Date(timeIntervalSince1970: seconds)
}
