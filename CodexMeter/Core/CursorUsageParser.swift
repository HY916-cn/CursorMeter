import Foundation

nonisolated struct CursorAuthStatus: Decodable, Equatable, Sendable {
    struct UserInfo: Decodable, Equatable, Sendable {
        let email: String?
        let userId: Int?
        let teamId: Int?
    }
    let status: String
    let isAuthenticated: Bool
    let userInfo: UserInfo?
    var subscriptionType: String?
    var loggedIn: Bool { status == "authenticated" && isAuthenticated }

    // Official status includes userInfo only after fetching the current account.
    // The about command cannot establish team scope and is never an identity fallback.
    var historyIdentity: String? {
        guard loggedIn, let userInfo else { return nil }
        let email = userInfo.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let person = userInfo.userId.map({ "id:\($0)" }) ?? email.flatMap({ $0.isEmpty ? nil : "email:\($0)" }) else { return nil }
        return "\(person)|\(userInfo.teamId.map { "team:\($0)" } ?? "personal")"
    }
}

nonisolated struct CursorAbout: Decodable {
    let cliVersion: String?
    let subscriptionTier: String?
}

nonisolated struct CursorUsageReading: Sendable {
    let windows: [CodexUsageWindow]
    let resetDescription: String?
    let onDemandDescription: String?
    let spendDescription: String?
}

nonisolated enum CursorCLIError: Error, Equatable {
    case notInstalled, notLoggedIn, subscriptionRequired, setupRequired
    case timedOut, communication, outputTooLarge, usageUnrecognized, usageCached, rateLimited, cancelled

    var localizationKey: String {
        switch self {
        case .notInstalled: return "error.cursor_not_found"
        case .notLoggedIn: return "error.cursor_not_logged_in"
        case .subscriptionRequired: return "error.cursor_subscription_required"
        case .setupRequired: return "error.cursor_setup_required"
        case .timedOut: return "error.cursor_request_timeout"
        case .usageUnrecognized: return "error.cursor_usage_unrecognized"
        case .usageCached: return "error.cursor_usage_cached"
        case .rateLimited: return "error.cursor_usage_rate_limited"
        case .outputTooLarge: return "error.cursor_output_too_large"
        case .communication, .cancelled: return "error.cursor_communication"
        }
    }
}

/// Cursor CLI 2026.10.22 usage-pager renders these labels and a closing footer.
/// The reset is only a UTC calendar date; it cannot establish a precise reset time.
nonisolated enum CursorUsageParser {
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\x1B\][^\x07]*(?:\x07|\x1B\\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x1B[()][A-Z0-9]|\x1B[78=>@-_]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\x00-\x08\x0B\x0C\x0E-\x1F]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func blockingError(in text: String) -> CursorCLIError? {
        guard let screen = CursorTerminalScreen.render(text) else { return nil }
        let lower = screen.lowercased()
        if ["do you trust", "trust this", "workspace trust", "sign in to cursor", "log in to cursor"].contains(where: lower.contains) { return .setupRequired }
        if lower.contains("not logged in") || lower.contains("run /login") { return .notLoggedIn }
        if lower.contains("rate limit") || lower.contains("resource_exhausted") { return .rateLimited }
        if lower.contains("cached usage") || lower.contains("last-known usage") { return .usageCached }
        if lower.contains("usage details are not available") || lower.contains("spend details are not available") { return .subscriptionRequired }
        if lower.contains("failed to load usage data") { return .communication }
        return nil
    }

    static func parse(_ text: String) -> CursorUsageReading? {
        guard let screen = CursorTerminalScreen.render(text), blockingError(in: screen) == nil,
              let start = screen.range(of: #"(?m)^\s*Usage(?:\s|$)"#, options: [.regularExpression, .backwards]) else { return nil }
        let panel = String(screen[start.lowerBound...])
        guard panel.contains("Esc to close"), panel.contains("View in dashboard:"),
              !panel.contains("Loading usage data") else { return nil }
        let reset = capture(#"\b(Resets [A-Za-z]{3,9} [0-9]{1,2}|Current period)\b"#, in: panel)
        if panel.contains("Personal spend for the current billing period") {
            guard let current = capture(#"(?m)^\s*Current(?: cycle)?\s*:?\s*(\$[0-9,]+(?:\.[0-9]{2})?)\s*$"#, in: panel),
                  let previous = capture(#"(?m)^\s*Previous(?: period)?\s*:?\s*(\$[0-9,]+(?:\.[0-9]{2})?)\s*$"#, in: panel) else { return nil }
            return CursorUsageReading(windows: [], resetDescription: reset, onDemandDescription: nil,
                                      spendDescription: "\(current) / \(previous)")
        }
        guard panel.contains("Monthly plan and on-demand usage") else { return nil }
        var windows: [CodexUsageWindow] = []
        for label in ["Included", "Auto", "API"] {
            guard let raw = capture("(?m)^\\s*\(label)\\s*:?\\s*([0-9]{1,3})% used(?:\\s+[█░]+)?\\s*$", in: panel),
                  let used = Int(raw), (0...100).contains(used) else { return nil }
            windows.append(CodexUsageWindow(id: "cursor-\(label.lowercased())", name: label, usedPercent: used,
                                            windowDurationMins: nil, resetsAt: nil))
        }
        guard let demand = capture(#"(?m)^\s*On-Demand\s*:?\s*(\$[0-9,]+(?:\.[0-9]{2})?(?: / \$[0-9,]+(?:\.[0-9]{2})?)?|Disabled|Unavailable)(?:\s+[█░—]+)?\s*$"#, in: panel),
              let detail = capture(#"(?m)^\s*(\$[0-9,]+(?:\.[0-9]{2})? remaining|No personal limit|No monthly limit|On-demand usage is off|On-demand limit unavailable)\s*$"#, in: panel) else { return nil }
        return CursorUsageReading(windows: windows, resetDescription: reset,
                                  onDemandDescription: "\(demand) · \(detail)", spendDescription: nil)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let match = matches.first,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
