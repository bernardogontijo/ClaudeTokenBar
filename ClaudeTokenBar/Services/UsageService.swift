import Foundation

@Observable
final class UsageService {
    var data = UsageData()
    private var timer: Timer?

    func start() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.pollInterval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetch() {
        Task.detached(priority: .utility) { [weak self] in
            let result = await Self.fetchUsage()
            await MainActor.run {
                self?.data = result
            }
        }
    }

    private static func fetchUsage() async -> UsageData {
        guard let token = KeychainHelper.getOAuthToken() else {
            var d = UsageData()
            d.error = "No OAuth token found"
            return d
        }

        guard let url = URL(string: Constants.usageAPIURL) else {
            var d = UsageData()
            d.error = "Invalid URL"
            return d
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-token-bar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                var d = UsageData()
                d.error = "HTTP \(code)"
                return d
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                var d = UsageData()
                d.error = "Invalid JSON"
                return d
            }

            var result = UsageData()
            result.lastUpdated = Date()

            if let fiveHour = json["five_hour"] as? [String: Any] {
                result.fiveHourUtilization = fiveHour["utilization"] as? Double ?? 0
                if let resetAt = fiveHour["resets_at"] as? String {
                    let (formatted, seconds) = parseResetTime(resetAt)
                    result.fiveHourResetIn = formatted
                    result.fiveHourResetSeconds = seconds
                }
            }

            if let sevenDay = json["seven_day"] as? [String: Any] {
                result.sevenDayUtilization = sevenDay["utilization"] as? Double ?? 0
                if let resetAt = sevenDay["resets_at"] as? String {
                    let (formatted, seconds) = parseResetTime(resetAt)
                    result.sevenDayResetIn = formatted
                    result.sevenDayResetSeconds = seconds
                }
            }

            return result
        } catch {
            var d = UsageData()
            d.error = error.localizedDescription
            return d
        }
    }

    private static func parseResetTime(_ dateString: String) -> (String, TimeInterval) {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]

        for formatter in [f1, f2] {
            if let date = formatter.date(from: dateString) {
                let remaining = max(date.timeIntervalSinceNow, 0)
                return (remaining.resetString, remaining)
            }
        }
        return ("", 0)
    }
}
