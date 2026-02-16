import SwiftUI
import Security

// MARK: - Constants

enum Constants {
    static let usageAPIURL = "https://api.anthropic.com/api/oauth/usage"
    static let keychainService = "Claude Code-credentials"
    static let pollInterval: TimeInterval = 60
    static let costPollInterval: TimeInterval = 300

    enum Pricing {
        static let opusInput: Double = 15.0
        static let opusOutput: Double = 75.0
        static let sonnetInput: Double = 3.0
        static let sonnetOutput: Double = 15.0
        static let haikuInput: Double = 0.25
        static let haikuOutput: Double = 1.25
        static let cacheReadDiscount: Double = 0.1
    }
}

// MARK: - Extensions

extension TimeInterval {
    var resetString: String {
        guard self > 0 else { return "now" }
        let total = Int(self)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 {
            return "\(days)d\(hours)h"
        } else if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Models

struct UsageData: Sendable {
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
}

// MARK: - Keychain

enum KeychainHelper {
    static func getOAuthToken() -> String? {
        if let token = getTokenViaSecurityFramework() { return token }
        return getTokenViaCLI()
    }

    private static func getTokenViaSecurityFramework() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return extractToken(from: data)
    }

    private static func getTokenViaCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", Constants.keychainService, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let jsonData = raw.data(using: .utf8) else { return nil }
        return extractToken(from: jsonData)
    }

    private static func extractToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        return token
    }
}

// MARK: - Usage Service

@MainActor
@Observable
final class UsageService {
    var data = UsageData()
    private var timer: Timer?

    func start() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetch() {
        Task {
            let result = await Self.fetchUsage()
            self.data = result
        }
    }

    private static func fetchUsage() async -> UsageData {
        guard let token = KeychainHelper.getOAuthToken() else {
            var d = UsageData(); d.error = "No OAuth token"; return d
        }
        guard let url = URL(string: Constants.usageAPIURL) else {
            var d = UsageData(); d.error = "Invalid URL"; return d
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-token-bar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                var d = UsageData(); d.error = "HTTP \(code)"; return d
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                var d = UsageData(); d.error = "Invalid JSON"; return d
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
            var d = UsageData(); d.error = error.localizedDescription; return d
        }
    }

    nonisolated private static func parseResetTime(_ dateString: String) -> (String, TimeInterval) {
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

// MARK: - Cost Service

@MainActor
@Observable
final class CostService {
    var dailyCost: Double = 0
    private var timer: Timer?

    func start() {
        calculate()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.costPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.calculate() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func calculate() {
        Task.detached {
            let cost = Self.calculateDailyCost()
            await MainActor.run { [cost] in self.dailyCost = cost }
        }
    }

    nonisolated private static func calculateDailyCost() -> Double {
        let projectsPath = NSString("~/.claude/projects").expandingTildeInPath
        let fm = FileManager.default
        var total: Double = 0

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: projectsPath),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate else { continue }
            guard df.string(from: modDate) == today else { continue }
            total += parseFileCost(url)
        }
        return total
    }

    nonisolated private static func parseFileCost(_ url: URL) -> Double {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        var cost: Double = 0
        for line in content.components(separatedBy: .newlines) {
            guard line.contains("\"usage\"") else { continue }
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let model = json["model"] as? String ?? ""
            let (inputPrice, outputPrice) = priceForModel(model)
            guard let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            let inputTokens = usage["input_tokens"] as? Double ?? 0
            let outputTokens = usage["output_tokens"] as? Double ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Double ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Double ?? 0
            cost += (inputTokens + cacheCreation) / 1_000_000 * inputPrice
            cost += cacheRead / 1_000_000 * inputPrice * Constants.Pricing.cacheReadDiscount
            cost += outputTokens / 1_000_000 * outputPrice
        }
        return cost
    }

    nonisolated private static func priceForModel(_ model: String) -> (Double, Double) {
        let m = model.lowercased()
        if m.contains("opus") { return (Constants.Pricing.opusInput, Constants.Pricing.opusOutput) }
        if m.contains("haiku") { return (Constants.Pricing.haikuInput, Constants.Pricing.haikuOutput) }
        return (Constants.Pricing.sonnetInput, Constants.Pricing.sonnetOutput)
    }
}

// MARK: - Views

struct UsageBar: View {
    let label: String
    let utilization: Double
    let resetIn: String

    private var barColor: Color {
        if utilization >= 80 { return Color(red: 0.97, green: 0.47, blue: 0.56) }
        if utilization >= 50 { return Color(red: 0.88, green: 0.69, blue: 0.41) }
        return Color(red: 0.62, green: 0.81, blue: 0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(utilization))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(barColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(geo.size.width * utilization / 100, 0), height: 6)
                }
            }
            .frame(height: 6)
            if !resetIn.isEmpty {
                Text("Resets in \(resetIn)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct MenuBarView: View {
    let usageService: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("Claude Token Usage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let date = usageService.data.lastUpdated {
                    Text(date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            if let error = usageService.data.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else {
                UsageBar(
                    label: "5-Hour Window",
                    utilization: usageService.data.fiveHourUtilization,
                    resetIn: usageService.data.fiveHourResetIn
                )
                UsageBar(
                    label: "7-Day Window",
                    utilization: usageService.data.sevenDayUtilization,
                    resetIn: usageService.data.sevenDayResetIn
                )
            }

            Divider()

            HStack {
                Button("Refresh") {
                    usageService.fetch()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    let usageService: UsageService

    var body: some View {
        let data = usageService.data
        let hasError = data.error != nil

        HStack(spacing: 2) {
            Image(systemName: hasError ? "exclamationmark.circle" : "brain.head.profile")
            if !hasError {
                Text("\(Int(data.fiveHourUtilization))·\(Int(data.sevenDayUtilization))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .onAppear {
            usageService.start()
        }
    }
}

// MARK: - App

@main
struct ClaudeTokenBarApp: App {
    @State private var usageService = UsageService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(usageService: usageService)
        } label: {
            MenuBarLabel(usageService: usageService)
        }
        .menuBarExtraStyle(.window)
    }
}
