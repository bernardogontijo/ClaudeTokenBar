import Foundation
import Security

enum KeychainHelper {
    static func getOAuthToken() -> String? {
        if let token = getTokenViaSecurityFramework() {
            return token
        }
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

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return extractToken(from: data)
    }

    private static func getTokenViaCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", Constants.keychainService, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        guard let jsonData = raw.data(using: .utf8) else { return nil }
        return extractToken(from: jsonData)
    }

    private static func extractToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            return token
        }

        return nil
    }
}
