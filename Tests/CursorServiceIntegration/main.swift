import Foundation
import Combine
import AppKit

final class AppSettings {
    enum Destination { case notifications }
    var notificationsEnabled = true
    var settingsDestination: Destination = .notifications
    var notificationThreshold = 20
    let historyIdentitySalt = "cursor-service-integration-fixture-salt"
    var historyRetention: HistoryRetention = .forever
    func clearSettingsError() {}
    func showSettingsError(_ message: String, destination: Destination) {}
}

final class NotificationManager {
    private(set) var evaluations = 0
    func requestAuthorization(completion: (Bool, String?) -> Void) { completion(true, nil) }
    func evaluate(windows: [CodexUsageWindow], threshold: Int) { evaluations += 1 }
    func resetEvaluationState() {}
}

final class PushNotificationService {
    private(set) var evaluations = 0
    init(settings: AppSettings) {}
    func evaluate(windows: [CodexUsageWindow]) { evaluations += 1 }
    func resetEvaluationState() {}
    func sendTestBark(completion: ((Bool, String?) -> Void)?) {}
    func sendTestGotify(completion: ((Bool, String?) -> Void)?) {}
}

enum L10n {
    static func string(_ key: String) -> String { key }
    static func format(_ key: String, _ arguments: CVarArg...) -> String { "\(key): \(arguments)" }
    static func formattedTime(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

/// This target excludes the real CLI client, so every refresh stays in the fixture.
nonisolated final class CursorCLIClient: @unchecked Sendable {
    struct Fixture: Sendable {
        let accounts: [CursorAuthStatus]
        let result: Result<[CodexUsageWindow], CursorCLIError>
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var next: Fixture?
    nonisolated(unsafe) private static var calls = 0
    private let fixture: Fixture

    static func configure(_ fixture: Fixture) {
        lock.lock()
        defer { lock.unlock() }
        next = fixture
        calls = 0
    }

    static var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    init() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let fixture = Self.next else { fatalError("Missing CLI fixture") }
        self.fixture = fixture
    }

    func fetch(onAccount: (CursorAuthStatus) -> Void) throws -> CursorUsageReading {
        Self.lock.lock()
        Self.calls += 1
        Self.lock.unlock()
        for account in fixture.accounts { onAccount(account) }
        let windows = try fixture.result.get()
        return CursorUsageReading(windows: windows, resetDescription: "Resets Nov 1", onDemandDescription: windows.isEmpty ? nil : "$0 · No monthly limit", spendDescription: windows.isEmpty ? "$12 / $20" : nil)
    }

    func cancel() {}
}

@main
struct Integration {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        print("PASS: \(message)")
    }

    static func settle() async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    static func until(_ message: String, timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        check(condition(), message)
    }

    static func account(_ email: String) throws -> CursorAuthStatus {
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "authenticated", "isAuthenticated": true,
            "userInfo": ["email": email, "teamId": 7], "subscriptionType": "pro"
        ])
        return try JSONDecoder().decode(CursorAuthStatus.self, from: data)
    }

    static func windows(used: Int, sampledAt: Date) -> [CodexUsageWindow] {
        ["included", "auto", "api"].enumerated().map { index, label in
            CodexUsageWindow(id: "cursor-\(label)", name: "quota.cursor_\(label)", usedPercent: used + index,
                             windowDurationMins: nil, resetsAt: nil)
        }
    }

    static func main() {
        // The production service uses Foundation timers on the main run loop.
        // Keep that loop running while the asynchronous checks await real callbacks.
        Task {
            do {
                try await runChecks()
                exit(EXIT_SUCCESS)
            } catch {
                fatalError("Service integration failed: \(error)")
            }
        }
        CFRunLoopRun()
    }

    static func runChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let settings = AppSettings()
        let accountA = try account("restart-a@example.invalid")
        let accountB = try account("restart-b@example.invalid")
        let keyA = HistoryAccountIdentity.make(accountType: "cursor", email: accountA.historyIdentity,
            salt: settings.historyIdentitySalt).key
        let keyB = HistoryAccountIdentity.make(accountType: "cursor", email: accountB.historyIdentity,
            salt: settings.historyIdentitySalt).key
        let sampledAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 600)
        let savedWindows = windows(used: 23, sampledAt: sampledAt)
        let store = try UsageHistoryStore(databaseURL: databaseURL)
        try await store.prepareDatabase()
        _ = try await store.recordQuotaSnapshots(savedWindows, at: sampledAt, isStale: false,
            source: .refresh, accountKey: keyA)
        let seededCount = try await store.quotaSamples(since: .distantPast, accountKey: keyA).count

        // A new model/service represents a fresh app process over an existing database.
        do {
            CursorCLIClient.configure(.init(accounts: [accountA], result: .failure(.usageCached)))
            let history = UsageHistoryModel(databaseURL: databaseURL)
            let notifications = NotificationManager()
            let push = PushNotificationService(settings: settings)
            let service = CodexUsageService(settings: settings, history: history,
                notificationManager: notifications, pushNotificationService: push)
            try await until("Restart restores saved quota after cached CLI failure") {
                service.windows.count == 3 && service.errorMessage != nil && !service.isRefreshInFlight
            }
            check(service.windows == savedWindows, "Restored quota keeps IDs, percentages, durations and resets")
            check(service.lastUpdated == sampledAt, "Restore keeps the original successful sample timestamp")
            check(service.isStale && !service.isLoading, "Restored quota remains visibly stale without a loading state")
            check(service.errorMessage?.contains("error.cursor_usage_cached") == true,
                  "Restore preserves the current cache-fallback error")
            service.refresh()
            service.refreshIfNeeded(maxAge: 0)
            try await settle()
            check(CursorCLIClient.fetchCount == 1, "Restart recovery and refresh clicks respect the failure cooldown")
            // Wait beyond the normal foreground age so this exercises the failure
            // cooldown rather than the wake handler's fresh-sample guard.
            try await Task.sleep(nanoseconds: UInt64((CursorRefreshSchedule.foregroundInterval + 0.2) * 1_000_000_000))
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await settle()
            check(CursorCLIClient.fetchCount == 1 && service.isStale,
                  "Wake preserves the failure cooldown after the normal refresh age")
            check(notifications.evaluations == 0 && push.evaluations == 0, "Restoration sends no quota notifications")
            let count = try await store.quotaSamples(since: .distantPast, accountKey: keyA).count
            check(count == seededCount, "Restoration adds no fresh history rows")
        }

        do {
            let freshWindows = windows(used: 37, sampledAt: sampledAt)
            CursorCLIClient.configure(.init(accounts: [accountA], result: .success(freshWindows)))
            let history = UsageHistoryModel(databaseURL: databaseURL)
            let notifications = NotificationManager()
            let push = PushNotificationService(settings: settings)
            let service = CodexUsageService(settings: settings, history: history,
                notificationManager: notifications, pushNotificationService: push)
            try await until("Fresh CLI response completes during startup history restoration") {
                service.lastUpdated != nil && !service.isStale && !service.isRefreshInFlight
            }
            try await settle()
            check(service.windows == freshWindows && service.lastUpdated! > sampledAt,
                  "A delayed restoration cannot overwrite a fresh CLI response")
            check(!service.isStale && service.errorMessage == nil, "Fresh response clears stale state and errors")
            check(notifications.evaluations == 1 && push.evaluations == 1,
                  "Only the fresh response evaluates quota notifications")
            service.setPopoverVisible(true)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await settle()
            check(CursorCLIClient.fetchCount == 1, "Immediate wake does not duplicate a fresh quota request")
            let firstUpdated = service.lastUpdated!
            try await until("Visible popover automatically refreshes without a manual request",
                            timeout: CursorRefreshSchedule.foregroundInterval + 5) {
                CursorCLIClient.fetchCount == 2 && !service.isRefreshInFlight
                    && service.lastUpdated! > firstUpdated
            }
            check(service.windows == freshWindows && !service.isStale,
                  "Automatic refresh preserves valid quota and advances its observation time")
            service.setPopoverVisible(false)
            let automaticUpdated = service.lastUpdated!
            try await Task.sleep(nanoseconds: UInt64((CursorRefreshSchedule.foregroundInterval + 0.2) * 1_000_000_000))
            check(CursorCLIClient.fetchCount == 2, "Hidden popover uses the longer background interval")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await until("Wake refreshes an aged sample before the background timer is due", timeout: 5) {
                CursorCLIClient.fetchCount == 3 && !service.isRefreshInFlight
                    && service.lastUpdated! > automaticUpdated
            }
        }

        do {
            CursorCLIClient.configure(.init(accounts: [accountA, accountB], result: .failure(.usageCached)))
            let history = UsageHistoryModel(databaseURL: databaseURL)
            let notifications = NotificationManager()
            let push = PushNotificationService(settings: settings)
            let service = CodexUsageService(settings: settings, history: history,
                notificationManager: notifications, pushNotificationService: push)
            try await until("Account switch completes while restoration is pending") {
                service.historyAccountKey == keyB && service.errorMessage != nil && !service.isRefreshInFlight
            }
            try await settle()
            check(service.windows.isEmpty && service.lastUpdated == nil,
                  "An account without history never receives another account's saved quota")
            check(!service.isLoading && notifications.evaluations == 0 && push.evaluations == 0,
                  "Failed refresh after account switch completes without notifications")
            let count = try await store.quotaSamples(since: .distantPast, accountKey: keyB).count
            check(count == 0, "Account switching does not copy history into the new account")
        }
        do {
            CursorCLIClient.configure(.init(accounts: [accountA], result: .success([])))
            let history = UsageHistoryModel(databaseURL: databaseURL)
            let service = CodexUsageService(settings: settings, history: history)
            try await until("Enterprise spending completes without quota percentages") {
                service.lastUpdated != nil && !service.isStale && !service.isRefreshInFlight
            }
            check(service.windows.isEmpty && service.spendUsageDescription == "$12 / $20",
                  "Enterprise spend is shown independently from percentages")
            let observed = service.lastUpdated
            CursorCLIClient.configure(.init(accounts: [accountA], result: .failure(.communication)))
            service.refreshIfNeeded(maxAge: 0)
            check(!service.isLoading, "Spending-only refresh retains the successful display")
            try await until("Enterprise failure completes") { service.errorMessage != nil && !service.isRefreshInFlight }
            check(service.isStale && service.spendUsageDescription == "$12 / $20" && service.lastUpdated == observed,
                  "Failed enterprise refresh preserves spending and its original observation time")
        }
        do {
            let unidentified = try JSONDecoder().decode(CursorAuthStatus.self,
                from: Data(#"{"status":"authenticated","isAuthenticated":true}"#.utf8))
            CursorCLIClient.configure(.init(accounts: [unidentified], result: .success(windows(used: 20, sampledAt: sampledAt))))
            let history = UsageHistoryModel(databaseURL: databaseURL)
            let notifications = NotificationManager()
            let push = PushNotificationService(settings: settings)
            let service = CodexUsageService(settings: settings, history: history,
                notificationManager: notifications, pushNotificationService: push)
            try await until("Unidentified account can display live percentages") { service.windows.count == 3 && !service.isRefreshInFlight }
            check(service.historyAccountKey == nil && notifications.evaluations == 0 && push.evaluations == 0,
                  "Incomplete identity disables history and alerts")
        }
        do {
            let freshWindows = windows(used: 20, sampledAt: sampledAt)
            CursorCLIClient.configure(.init(accounts: [accountA], result: .success(freshWindows)))
            let history = UsageHistoryModel(databaseURL: databaseURL)
            let service = CodexUsageService(settings: settings, history: history)
            try await until("Initial account plan is available") { service.planType == "pro" && !service.isRefreshInFlight }
            var statusOnly = accountA
            statusOnly.subscriptionType = nil
            CursorCLIClient.configure(.init(accounts: [statusOnly], result: .success(freshWindows)))
            service.refreshIfNeeded(maxAge: 0)
            try await until("Same-account status refresh completes") { !service.isRefreshInFlight }
            check(service.planType == "pro", "Intermediate status preserves the identified account's known plan")

            var otherStatus = accountB
            otherStatus.subscriptionType = nil
            CursorCLIClient.configure(.init(accounts: [otherStatus], result: .success(freshWindows)))
            service.refreshIfNeeded(maxAge: 0)
            try await until("New account status refresh completes") { !service.isRefreshInFlight }
            check(service.planType == "Cursor" && service.accountDescription == "Cursor",
                  "Account change clears the old plan and shows Cursor once")

            CursorCLIClient.configure(.init(accounts: [accountB], result: .success(freshWindows)))
            service.refreshIfNeeded(maxAge: 0)
            try await until("New account plan arrives") { service.planType == "pro" && !service.isRefreshInFlight }
            let unidentified = try JSONDecoder().decode(CursorAuthStatus.self,
                from: Data(#"{"status":"authenticated","isAuthenticated":true}"#.utf8))
            CursorCLIClient.configure(.init(accounts: [unidentified], result: .success(freshWindows)))
            service.refreshIfNeeded(maxAge: 0)
            try await until("Unidentified account status refresh completes") { !service.isRefreshInFlight }
            check(service.planType == "Cursor" && service.accountDescription == "Cursor",
                  "Missing identity clears the prior account's plan")
        }
        print("Cursor service integration checks passed: real SQLite restart recovery, stale state, timestamps, cooldown, automatic timer, wake handling, fresh response, account isolation.")
    }
}
