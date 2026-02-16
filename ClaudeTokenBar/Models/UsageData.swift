import Foundation

struct UsageData {
    var fiveHourUtilization: Double = 0
    var fiveHourResetIn: String = ""
    var fiveHourResetSeconds: TimeInterval = 0
    var fiveHourWindowSeconds: TimeInterval = 5 * 3600

    var sevenDayUtilization: Double = 0
    var sevenDayResetIn: String = ""
    var sevenDayResetSeconds: TimeInterval = 0
    var sevenDayWindowSeconds: TimeInterval = 7 * 24 * 3600

    var dailyCost: Double = 0
    var lastUpdated: Date?
    var error: String?

    var fiveHourTimePercent: Double {
        guard fiveHourWindowSeconds > 0, fiveHourResetSeconds > 0 else { return 0 }
        let elapsed = fiveHourWindowSeconds - fiveHourResetSeconds
        return min(max(elapsed / fiveHourWindowSeconds * 100, 0), 100)
    }

    var sevenDayTimePercent: Double {
        guard sevenDayWindowSeconds > 0, sevenDayResetSeconds > 0 else { return 0 }
        let elapsed = sevenDayWindowSeconds - sevenDayResetSeconds
        return min(max(elapsed / sevenDayWindowSeconds * 100, 0), 100)
    }
}
