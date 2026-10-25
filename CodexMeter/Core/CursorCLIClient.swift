import Foundation
import Darwin

/// Runs only the installed Cursor CLI's account-status and local /usage commands.
/// Calls are serialized by the service; all captures and lifetimes are bounded.
nonisolated final class CursorCLIClient: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcess: Process?
    private var isCancelled = false
    static let maximumCaptureBytes = 256 * 1_024

    static var probeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CursorMeter/CLI", isDirectory: true)
    }

    static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let fm = FileManager.default
        let candidates = [home.appendingPathComponent(".local/bin/agent"),
                          home.appendingPathComponent(".local/bin/cursor-agent"),
                          URL(fileURLWithPath: "/opt/homebrew/bin/cursor-agent"),
                          URL(fileURLWithPath: "/usr/local/bin/cursor-agent")]
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    private let executableOverride: URL?
    private let directoryOverride: URL?

    init(executable: URL? = nil, directory: URL? = nil) {
        executableOverride = executable
        directoryOverride = directory
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let process = activeProcess
        lock.unlock()
        if let process {
            Self.terminate(process, ownsGroup: getpgid(process.processIdentifier) == process.processIdentifier)
        }
    }

    private static func terminate(_ process: Process, ownsGroup: Bool) {
        let pid = process.processIdentifier
        if ownsGroup { kill(-pid, SIGTERM) }
        else if process.isRunning { process.terminate() }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while (ownsGroup ? kill(-pid, 0) == 0 : process.isRunning)
                && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
        // A descendant can outlive the CLI leader; terminate the owned group even
        // after Foundation reports the leader's exit.
        if ownsGroup { kill(-pid, SIGKILL) }
        else if process.isRunning { kill(pid, SIGKILL) }
    }

    func fetch(onAccount: (CursorAuthStatus) -> Void) throws -> CursorUsageReading {
        guard let executable = executableOverride ?? Self.locate() else { throw CursorCLIError.notInstalled }
        let directory = directoryOverride ?? Self.probeDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var account = try authStatus(executable: executable, directory: directory)
        onAccount(account)
        guard account.loggedIn else { throw CursorCLIError.notLoggedIn }
        if let output = try? capture(executable: executable, arguments: ["about", "--format", "json"],
                                    directory: directory, usage: false, timeout: 10),
           let about = try? JSONDecoder().decode(CursorAbout.self, from: Data(CursorUsageParser.clean(output).utf8)) {
            account.subscriptionType = about.subscriptionTier
            onAccount(account)
        }
        let output = try capture(executable: executable, arguments: [
            "--disable-auto-update", "--disable-indexing", "--disable-codebase-ref",
            "--disable-project-configs", "--mode", "ask"
        ], directory: directory, usage: true, timeout: 30)
        let finalAccount = try authStatus(executable: executable, directory: directory)
        if account.loggedIn != finalAccount.loggedIn || account.userInfo != finalAccount.userInfo {
            onAccount(finalAccount)
            throw CursorCLIError.communication
        }
        guard let reading = CursorUsageParser.parse(output) else { throw CursorCLIError.usageUnrecognized }
        return reading
    }

    private func authStatus(executable: URL, directory: URL) throws -> CursorAuthStatus {
        let output = try capture(executable: executable, arguments: ["status", "--format", "json"],
                                 directory: directory, usage: false, timeout: 10)
        guard let status = try? JSONDecoder().decode(CursorAuthStatus.self,
            from: Data(CursorUsageParser.clean(output).utf8)) else { throw CursorCLIError.communication }
        return status
    }

    // Only submit after the CLI recognizes its own local slash command in the palette.
    // No positional prompt is passed and setup/trust dialogs receive no input.
    func capture(executable: URL, arguments: [String], directory: URL,
                 usage: Bool, timeout: TimeInterval) throws -> String {
        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: 100, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw CursorCLIError.communication }
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        defer {
            try? masterHandle.close()
            try? slaveHandle.close()
        }
        if usage {
            // Cursor can paint its prompt before switching stdin to raw mode.
            // Configure this owned PTY before launch so the slash palette receives
            // individual input immediately rather than a canonical line buffer.
            var terminal = termios()
            guard tcgetattr(slave, &terminal) == 0 else { throw CursorCLIError.communication }
            cfmakeraw(&terminal)
            guard tcsetattr(slave, TCSANOW, &terminal) == 0 else { throw CursorCLIError.communication }
        }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        _ = fcntl(master, F_SETNOSIGPIPE, 1)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        var environment = CodexProcessEnvironment.make(baseEnvironment: ProcessInfo.processInfo.environment,
            executableURL: executable, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        environment["PWD"] = directory.path
        environment["TERM"] = "xterm-256color"
        environment["NO_COLOR"] = "1"
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment
        lock.lock()
        if isCancelled {
            lock.unlock()
            throw CursorCLIError.cancelled
        }
        do {
            try process.run()
            activeProcess = process
            lock.unlock()
        } catch {
            lock.unlock()
            throw CursorCLIError.communication
        }
        try? slaveHandle.close()
        let pid = process.processIdentifier
        let ownsGroup = getpgid(pid) == pid
        defer {
            Self.terminate(process, ownsGroup: ownsGroup)
            lock.lock()
            if activeProcess === process { activeProcess = nil }
            lock.unlock()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var lastRead = ProcessInfo.processInfo.systemUptime
        var data = Data()
        var typedCommand = false
        var submittedCommand = false
        var bytes = [UInt8](repeating: 0, count: 8192)
        while ProcessInfo.processInfo.systemUptime < deadline {
            lock.lock()
            let cancelled = isCancelled
            lock.unlock()
            if cancelled { throw CursorCLIError.cancelled }
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, 100)
            let count = Darwin.read(master, &bytes, bytes.count)
            if count > 0 {
                guard data.count + count <= Self.maximumCaptureBytes else { throw CursorCLIError.outputTooLarge }
                data.append(contentsOf: bytes.prefix(count))
                lastRead = ProcessInfo.processInfo.systemUptime
                if usage, let error = CursorUsageParser.blockingError(in: String(decoding: data, as: UTF8.self)) {
                    throw error
                }
            } else if count < 0 && errno != EAGAIN && errno != EINTR && errno != EIO {
                throw CursorCLIError.communication
            }
            // A child may close its terminal before exiting; avoid spinning on POLLHUP.
            if count <= 0, descriptor.revents & Int16(POLLHUP) != 0, process.isRunning { usleep(20_000) }
            let output = String(decoding: data, as: UTF8.self)
            if usage, let screen = CursorTerminalScreen.render(output) {
                if !typedCommand, screen.contains("Plan, search, build anything") {
                    let command = Array("/usage".utf8)
                    guard Darwin.write(master, command, command.count) == command.count else { throw CursorCLIError.communication }
                    typedCommand = true
                } else if typedCommand, !submittedCommand, screen.contains("Show plan and on-demand usage") {
                    var enter: UInt8 = 13
                    guard Darwin.write(master, &enter, 1) == 1 else { throw CursorCLIError.communication }
                    submittedCommand = true
                }
            }
            if usage, ProcessInfo.processInfo.systemUptime - lastRead >= 0.8,
               CursorUsageParser.parse(output) != nil { return output }
            if !process.isRunning && count <= 0 {
                if usage, CursorUsageParser.parse(output) == nil { throw CursorCLIError.usageUnrecognized }
                return output
            }
        }
        throw CursorCLIError.timedOut
    }
}
