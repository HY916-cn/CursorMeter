import Foundation
import Darwin

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}

// Text layout is based on the official 2026.10.22 usage-pager and a live capture.
let panel = """
Usage • Premium                                                 Resets Nov 1
Monthly plan and on-demand usage

Category        Current             Usage
Included        23% used            ███░░░░░░░
  Auto          8% used             █░░░░░░░░░
  API           15% used            ██░░░░░░░░
On-Demand       $0                  ——————————

No monthly limit

View in dashboard: cursor.com/dashboard?tab=usage

Esc to close
"""

if CommandLine.arguments.contains("--fixture-cli") {
    let arguments = Array(CommandLine.arguments.dropFirst(2))
    let mode = ProcessInfo.processInfo.environment["CURSORMETER_TEST_MODE"] ?? "success"
    if arguments == ["status", "--format", "json"] {
        if mode == "signed-out" { print(#"{"status":"unauthenticated","isAuthenticated":false}"#) }
        else if mode == "unidentified" { print(#"{"status":"authenticated","isAuthenticated":true}"#) }
        else { print(#"{"status":"authenticated","isAuthenticated":true,"userInfo":{"email":"fixture@example.invalid","userId":42,"teamId":7}}"#) }
        exit(0)
    }
    if arguments == ["about", "--format", "json"] {
        print(#"{"cliVersion":"2026.10.22-27dcf5f","subscriptionTier":"Premium"}"#); exit(0)
    }
    expect(arguments == ["--disable-auto-update", "--disable-indexing", "--disable-codebase-ref", "--disable-project-configs", "--mode", "ask"], "Only the verified interactive flags are sent")
    expect(URL(fileURLWithPath: ProcessInfo.processInfo.environment["PWD"] ?? "").resolvingSymlinksInPath().path == URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path,
           "CLI PWD matches actual probe directory")
    var terminal = termios()
    tcgetattr(STDIN_FILENO, &terminal); cfmakeraw(&terminal); tcsetattr(STDIN_FILENO, TCSANOW, &terminal)
    if mode == "trust" { print("Do you trust the contents of this directory?"); fflush(stdout); sleep(30); exit(1) }
    print("Plan, search, build anything"); fflush(stdout)
    var input = [UInt8](repeating: 0, count: 7)
    var count = 0
    while count < 7 {
        var byte: UInt8 = 0
        guard Darwin.read(STDIN_FILENO, &byte, 1) == 1 else { exit(2) }
        input[count] = byte; count += 1
        if count == 6 {
            expect(String(decoding: input.prefix(6), as: UTF8.self) == "/usage", "Only the local usage command is typed")
            if mode != "unsupported" { print("Show plan and on-demand usage"); fflush(stdout) }
        }
    }
    expect(input.last == 13, "Submission is a single Return")
    print("\u{1B}[2J\u{1B}[H" + panel); fflush(stdout)
    sleep(30); exit(0)
}

let reading = CursorUsageParser.parse(panel)!
expect(reading.windows.map(\.remainingPercent) == [77, 92, 85], "Each distinct included pool retains its percentage")
expect(reading.windows.map(\.id) == ["cursor-included", "cursor-auto", "cursor-api"], "Stable pool identities")
expect(reading.windows.allSatisfy { $0.windowDurationMins == nil && $0.resetsAt == nil }, "Date-only reset cannot fabricate window duration or exact timestamp")
expect(reading.resetDescription == "Resets Nov 1", "Official reset label preserved")
expect(reading.onDemandDescription == "$0 · No monthly limit", "Uncapped spending is separate from quota")
for invalid in [panel.replacingOccurrences(of: "23%", with: "101%"), panel.replacingOccurrences(of: "Esc to close", with: ""), panel.replacingOccurrences(of: "  API           15% used            ██░░░░░░░░", with: ""), panel + "\nLoading usage data..."] {
    expect(CursorUsageParser.parse(invalid) == nil, "Malformed/incomplete panel stays unavailable")
}
let compact = """
Usage • Pro   Current period
Monthly plan and on-demand usage
Included: 0% used
Auto: 0% used
API: 0% used
On-Demand: $12 / $50
$38 remaining
View in dashboard: cursor.com/dashboard?tab=usage
Esc to close
"""
expect(CursorUsageParser.parse(compact)?.onDemandDescription == "$12 / $50 · $38 remaining", "Compact monetary limit preserved")
let enterprise = """
Usage • Enterprise  Resets Nov 1
Personal spend for the current billing period
Current cycle     $17.20
▁▂▃▄
Previous period   $25
▂▃▅▆
View in dashboard: cursor.com/dashboard?tab=usage
Esc to close
"""
expect(CursorUsageParser.parse(enterprise)?.windows.isEmpty == true, "Enterprise spend has no fabricated quota")
expect(CursorUsageParser.parse(enterprise)?.spendDescription == "$17.20 / $25", "Enterprise spending remains visible")
expect(CursorUsageParser.parse("\u{1B}[2J\u{1B}[H" + panel)?.windows == reading.windows, "ANSI final screen parsing")
expect(CursorUsageParser.parse(panel + "\u{1B}[") == nil, "Incomplete terminal control waits for data")
expect(CursorUsageParser.parse("\u{1B}[>1u\u{1B}[?1004h\u{1B}[?2004h\u{1B}[?2031h\u{1B}[?25l" + panel)?.windows.count == 3, "Observed Cursor keyboard protocol negotiation preserves the final screen")
expect(CursorTerminalScreen.render("\u{1B}[9999B") == nil, "Terminal screen dimensions bounded")
expect(CursorUsageParser.blockingError(in: "Do you trust the contents of this directory?") == .setupRequired, "Trust dialog not accepted")
expect(CursorUsageParser.blockingError(in: "Not logged in. Run /login first.") == .notLoggedIn, "Logged out state classified")

let now = Date()
var schedule = CursorRefreshSchedule()
schedule.started(at: now)
expect(!schedule.mayRefresh(at: now.addingTimeInterval(9), manual: true), "Manual clicks limited to ten seconds")
expect(schedule.nextAutomaticAttempt(isPopoverVisible: true) == now.addingTimeInterval(10), "Foreground ten seconds")
expect(schedule.nextAutomaticAttempt(isPopoverVisible: false) == now.addingTimeInterval(60), "Background sixty seconds")
for delay in [300.0, 600, 1200, 1800, 1800] {
    schedule.failed(at: now, usageUnavailable: true)
    expect(schedule.retryAfter == now.addingTimeInterval(delay), "Rate-limit backoff capped")
    expect(!schedule.mayRefresh(at: now, manual: true), "Manual refresh honors backoff")
}
schedule.succeeded(); expect(schedule.retryAfter == nil, "Successful read clears backoff")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-cli-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let executable = directory.appendingPathComponent("agent")
let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
// A local shell wrapper launches this same test binary; it never contacts a service.
try "#!/bin/sh\nexec '\(binary.replacingOccurrences(of: "'", with: "'\\''"))' --fixture-cli \"$@\"\n".write(to: executable, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
var accounts: [CursorAuthStatus] = []
let fetched = try CursorCLIClient(executable: executable, directory: directory).fetch { accounts.append($0) }
expect(fetched.windows.map(\.id) == reading.windows.map(\.id) && fetched.windows.map(\.remainingPercent) == reading.windows.map(\.remainingPercent), "Actual production client reads fake executable through JSON and interactive PTY")
expect(accounts.last?.historyIdentity == "id:42|team:7", "Official user and team scope isolate history")
expect(accounts.last?.subscriptionType == "Premium", "Plan is read through official about JSON")

func expectError(_ expected: CursorCLIError, executable: URL, arguments: [String], usage: Bool, timeout: TimeInterval) {
    do {
        _ = try CursorCLIClient().capture(executable: executable, arguments: arguments, directory: directory, usage: usage, timeout: timeout)
        fatalError("Expected \(expected)")
    } catch let error as CursorCLIError { expect(error == expected, "Expected \(expected), received \(error)") }
    catch { fatalError("Unexpected capture error") }
}
expectError(.outputTooLarge, executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], usage: false, timeout: 2)
expectError(.timedOut, executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], usage: false, timeout: 0.2)
for mode in ["trust", "unsupported"] {
    setenv("CURSORMETER_TEST_MODE", mode, 1)
    expectError(mode == "trust" ? .setupRequired : .timedOut, executable: executable,
                arguments: ["--disable-auto-update", "--disable-indexing", "--disable-codebase-ref", "--disable-project-configs", "--mode", "ask"], usage: true, timeout: 1)
}
setenv("CURSORMETER_TEST_MODE", "unidentified", 1)
accounts = []
_ = try CursorCLIClient(executable: executable, directory: directory).fetch { accounts.append($0) }
expect(accounts.allSatisfy { $0.historyIdentity == nil }, "Incomplete identity remains live-only even with about metadata")
unsetenv("CURSORMETER_TEST_MODE")
let cancelled = CursorCLIClient(); cancelled.cancel()
do { _ = try cancelled.fetch { _ in }; fatalError("Cancelled client must not launch") }
catch let error as CursorCLIError { expect(error == .cancelled, "Cancellation") }
let descendant = try CursorCLIClient().capture(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 30 >/dev/null 2>&1 & echo $!"], directory: directory, usage: false, timeout: 2)
let pid = Int32(descendant.trimmingCharacters(in: .whitespacesAndNewlines))!
let deadline = Date().addingTimeInterval(1)
while kill(pid, 0) == 0 && Date() < deadline { usleep(10_000) }
expect(kill(pid, 0) != 0, "Process group cleanup includes descendants")
print("Cursor CLI checks passed: real client, fixture executable, parser, monetary usage, identity, interactive-only submission, bounds, cleanup, and refresh schedule.")
if CommandLine.arguments.contains("--live") {
    let live = try CursorCLIClient().fetch { account in
        print("Live authenticated=\(account.loggedIn), identified=\(account.historyIdentity != nil)")
    }
    print("Live pools=\(live.windows.count), remaining=\(live.windows.map(\.remainingPercent)), reset=\(live.resetDescription ?? "unknown")")
}
