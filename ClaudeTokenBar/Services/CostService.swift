import Foundation

@Observable
final class CostService {
    var dailyCost: Double = 0
    private var timer: Timer?
    private var fileCache: [String: Double] = [:]

    func start() {
        calculate()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.costPollInterval, repeats: true) { [weak self] _ in
            self?.calculate()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func calculate() {
        Task.detached(priority: .utility) { [weak self] in
            let cost = Self.calculateDailyCost(cache: self?.fileCache ?? [:])
            await MainActor.run {
                self?.dailyCost = cost.total
                self?.fileCache = cost.cache
            }
        }
    }

    private static func calculateDailyCost(cache: [String: Double]) -> (total: Double, cache: [String: Double]) {
        let projectsPath = NSString("~/.claude/projects").expandingTildeInPath
        let fm = FileManager.default
        var newCache = cache
        var total: Double = 0

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: projectsPath),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, newCache)
        }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }

            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate else { continue }

            let modDateStr = df.string(from: modDate)
            guard modDateStr == today else { continue }

            let cacheKey = "\(url.path):\(modDate.timeIntervalSince1970)"
            if let cached = newCache[cacheKey] {
                total += cached
                continue
            }

            let fileCost = parseFileCost(url)
            newCache[cacheKey] = fileCost
            total += fileCost
        }

        return (total, newCache)
    }

    private static func parseFileCost(_ url: URL) -> Double {
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

            let inputCost = (inputTokens + cacheCreation) / 1_000_000 * inputPrice
            let cacheReadCost = cacheRead / 1_000_000 * inputPrice * Constants.Pricing.cacheReadDiscount
            let outputCost = outputTokens / 1_000_000 * outputPrice

            cost += inputCost + cacheReadCost + outputCost
        }

        return cost
    }

    private static func priceForModel(_ model: String) -> (input: Double, output: Double) {
        let m = model.lowercased()
        if m.contains("opus") {
            return (Constants.Pricing.opusInput, Constants.Pricing.opusOutput)
        } else if m.contains("haiku") {
            return (Constants.Pricing.haikuInput, Constants.Pricing.haikuOutput)
        }
        return (Constants.Pricing.sonnetInput, Constants.Pricing.sonnetOutput)
    }
}
