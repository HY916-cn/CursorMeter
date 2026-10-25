import Foundation

/// Last successful account-scoped quota, retaining the age of its observations.
nonisolated struct CursorUsageSnapshot: Sendable {
    let windows: [CodexUsageWindow]
    let sampledAt: Date

    static func fromHistorySamples(_ samples: [QuotaHistorySample]) -> CursorUsageSnapshot? {
        let ids = ["cursor-included", "cursor-auto", "cursor-api"]
        let valid = samples.filter { sample in
            !sample.isStale && sample.source == .refresh && (0...100).contains(sample.remainingPercent)
                && ids.contains(sample.windowID) && sample.windowDurationMins == nil && sample.resetsAt == nil
                && sample.sampledAt.timeIntervalSince1970.isFinite
        }
        guard let newest = valid.map(\.sampledAt).max() else { return nil }
        let recent = valid.filter { newest.timeIntervalSince($0.sampledAt) <= 15 * 60 }
        let windows = ids.compactMap { id -> CodexUsageWindow? in
            guard let sample = recent.filter({ $0.windowID == id }).max(by: { $0.sampledAt < $1.sampledAt }) else { return nil }
            return CodexUsageWindow(id: id, name: sample.windowName, usedPercent: 100 - sample.remainingPercent,
                                    windowDurationMins: nil, resetsAt: nil)
        }
        guard windows.count == ids.count else { return nil }
        return CursorUsageSnapshot(windows: windows, sampledAt: recent.map(\.sampledAt).min()!)
    }
}
