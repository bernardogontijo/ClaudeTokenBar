import Foundation

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
