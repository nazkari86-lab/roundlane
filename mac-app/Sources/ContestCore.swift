import CryptoKit
import Foundation

enum ContestCore {
    static let address = URL(string: "http://127.0.0.1:18765/")!
    static let fallbackCode = "1234"
    static let usabilityKeys = ["allowFind", "enableZoomPage", "enableZoomText", "showTime",
        "browserWindowAllowReload", "newBrowserWindowAllowReload", "showReloadWarning",
        "newBrowserWindowShowReloadWarning", "enableBrowserWindowToolbar", "allowBrowsingBackForward"]
    static let allowExpressions = [
        "^http://127\\.0\\.0\\.1:18765/",
        "^https://codeforces\\.com/",
        "^https://assets\\.codeforces\\.com/",
        "^https://challenges\\.cloudflare\\.com/",
        "^https://www\\.onlinegdb\\.com/([?#].*)?$",
        "^https://onlinegdb\\.com/([?#].*)?$",
        "^https://www\\.onlinegdb\\.com/online_c[+][+]_compiler([?#].*)?$",
        "^https://www\\.onlinegdb\\.com/public/",
        "^https://www\\.onlinegdb\\.com/socket\\.io/",
        "^wss://www\\.onlinegdb\\.com/socket\\.io/",
        "^https://in2\\.onlinegdb\\.com/socket\\.io/",
        "^wss://in2\\.onlinegdb\\.com/socket\\.io/",
        "^https://www\\.onlinegdb\\.com/beautify([?#].*)?$",
        "^blob:https://www\\.onlinegdb\\.com/",
        "^https://stg\\.html-load\\.com/loader\\.min\\.js([?#].*)?$",
        "^https://www\\.onlinegdb\\.com/cdn-cgi/challenge-platform/",
        "^https://cdn4\\.buysellads\\.net/pub/onlinegdb\\.js([?#].*)?$",
        "^https://m\\.servedby-buysellads\\.com/monetization\\.js([?#].*)?$",
        "^https://cdn\\.carbonads\\.com/carbon\\.js([?#].*)?$",
        "^https://srv\\.buysellads\\.com/ads/",
        "^https://srv\\.carbonads\\.net/ads/",
        "^https://cdn4\\.buysellads\\.net/uu/",
        "^https://check-adblock\\.buysellads\\.net/i\\.gif([?#].*)?$",
        "^https://pagead2\\.googlesyndication\\.com/pagead/js/adsbygoogle\\.js([?#].*)?$",
        "^https://html-load\\.com/loader\\.min\\.js([?#].*)?$", "^https://cdnjs\\.cloudflare\\.com/ajax/libs/bootstrap-select/1\\.12\\.4/js/bootstrap-select\\.min\\.js([?#].*)?$",
        "^https://cdnjs\\.cloudflare\\.com/ajax/libs/bootstrap-select/1\\.12\\.4/css/bootstrap-select\\.min\\.css([?#].*)?$",
        "^https://unpkg\\.com/react@17[.0-9]*/umd/react\\.production\\.min\\.js([?#].*)?$",
        "^https://unpkg\\.com/react-dom@17[.0-9]*/umd/react-dom\\.production\\.min\\.js([?#].*)?$"
    ]

    static func groupURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = text.hasPrefix("codeforces.com/") ? "https://\(text)" : text
        guard let url = URL(string: candidate),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https",
              parts.host == "codeforces.com",
              parts.port == nil,
              parts.user == nil,
              parts.password == nil, parts.fragment == nil else { return nil }
        let segments = url.pathComponents
        guard segments.count >= 3, segments[1] == "group",
              segments[2].range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            return nil
        }
        return url
    }

    static func validCode(_ code: String) -> Bool {
        (4...12).contains(code.utf8.count)
            && code.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
            }
    }

    static func passwordHash(_ code: String) -> String {
        SHA256.hash(data: Data(code.utf8)).map { String(format: "%02X", $0) }.joined()
    }

    static func makeProfile(from template: URL, code: String) throws -> Data {
        guard validCode(code),
              let source = try PropertyListSerialization.propertyList(from: Data(contentsOf: template), format: nil)
                as? [String: Any] else {
            throw NSError(domain: "Roundlane", code: 1, userInfo: [NSLocalizedDescriptionKey: "Профиль SEB не найден или пароль выхода неверного формата."])
        }
        var settings = source
        for key in usabilityKeys { settings[key] = true }
        settings["allowQuit"] = true
        settings["showQuitButton"] = true
        settings["hashedQuitPassword"] = passwordHash(code)
        settings["startURL"] = address.absoluteString
        settings["sebConfigPurpose"] = 0
        settings["URLFilterEnable"] = true
        settings["URLFilterEnableContentFilter"] = true
        settings["allowPreferencesWindow"] = false
        settings["browserWindowAllowAddressBar"] = false
        settings["newBrowserWindowAllowAddressBar"] = false
        settings["allowDownloads"] = true
        settings["allowUploads"] = true
        settings["downloadAndOpenSebConfig"] = false
        settings["URLFilterRules"] = allowExpressions.map { expression in
            ["action": 1, "active": true, "expression": expression, "regex": true] as [String: Any]
        }
        let output = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        guard profileIsRecoverable(output, code: code) else {
            throw NSError(domain: "Roundlane", code: 3, userInfo: [NSLocalizedDescriptionKey: "Не удалось проверить кнопку и пароль выхода из SEB."])
        }
        return output
    }

    static func profileIsRecoverable(_ data: Data, code: String) -> Bool {
        guard let settings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rules = settings["URLFilterRules"] as? [[String: Any]],
              rules.count == allowExpressions.count else { return false }
        let rulesMatch = zip(rules, allowExpressions).allSatisfy { rule, expression in
            rule["active"] as? Bool == true
                && rule["regex"] as? Bool == true
                && rule["action"] as? Int == 1
                && rule["expression"] as? String == expression
        }
        return settings["allowQuit"] as? Bool == true
            && settings["showQuitButton"] as? Bool == true
            && settings["hashedQuitPassword"] as? String == passwordHash(code)
            && settings["startURL"] as? String == address.absoluteString
            && settings["URLFilterEnable"] as? Bool == true
            && settings["URLFilterEnableContentFilter"] as? Bool == true
            && settings["allowPreferencesWindow"] as? Bool == false
            && settings["browserWindowAllowAddressBar"] as? Bool == false
            && settings["newBrowserWindowAllowAddressBar"] as? Bool == false
            && settings["allowDownloads"] as? Bool == true
            && settings["allowUploads"] as? Bool == true
            && settings["downloadAndOpenSebConfig"] as? Bool == false
            && rulesMatch
            && usabilityKeys.allSatisfy { settings[$0] as? Bool == true }
    }
}
