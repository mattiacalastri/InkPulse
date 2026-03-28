import Foundation

/// Shared computed stats derived from AppState.
/// Used by both PopoverView and LiveTab to eliminate duplicated computed properties.
@MainActor
struct DashboardStats {
    let appState: AppState

    var snaps: [MetricsSnapshot] {
        appState.metricsEngine.sessions.values
            .sorted { $0.lastEventTime > $1.lastEventTime }
    }

    var health: Int { appState.metricsEngine.aggregateHealth }

    var totalCost: Double {
        snaps.map(\.costEUR).reduce(0, +)
    }

    var avgCacheHit: Double {
        guard !snaps.isEmpty else { return 0 }
        return snaps.map(\.cacheHit).reduce(0, +) / Double(snaps.count)
    }

    var avgErrorRate: Double {
        guard !snaps.isEmpty else { return 0 }
        return snaps.map(\.errorRate).reduce(0, +) / Double(snaps.count)
    }

    var totalAgents: Int {
        snaps.map(\.subagentCount).reduce(0, +)
    }

    var peakTokenMin: Double {
        appState.tokenHistory.max() ?? 0
    }

    var avgTokenMin: Double {
        let h = appState.tokenHistory
        guard !h.isEmpty else { return 0 }
        return h.reduce(0, +) / Double(h.count)
    }

    var uptimeMin: Double {
        guard let earliest = snaps.map(\.startTime).min() else { return 0 }
        return Date().timeIntervalSince(earliest) / 60.0
    }

    var throughputPerAgent: Double {
        guard !snaps.isEmpty else { return 0 }
        return avgTokenMin / Double(snaps.count)
    }

    var avgContextPercent: Double {
        let withCtx = snaps.filter { $0.lastContextTokens > 0 }
        guard !withCtx.isEmpty else { return 0 }
        return withCtx.map(\.contextPercent).reduce(0, +) / Double(withCtx.count)
    }

    var config: InkPulseConfig {
        ConfigLoader.load()
    }

    // MARK: - Quota (from Anthropic API)

    var quotaSnapshot: QuotaSnapshot? {
        appState.quotaSnapshot
    }

    /// Remaining quota as fraction 0.0-1.0 (for color coding).
    var quotaRemainingPercent: Double? {
        quotaSnapshot?.primaryRemainingPercent
    }

    /// Utilization as display string.
    var quotaUsedDisplay: String? {
        guard let fh = quotaSnapshot?.fiveHour else { return nil }
        return String(format: "%.0f%%", fh.utilization)
    }

    var planName: String? {
        quotaSnapshot?.plan.rawValue
    }

    // MARK: - Budget (local)

    var budgetPercent: Double? {
        let budget = config.dailyBudgetEUR
        guard budget > 0 else { return nil }
        return totalCost / budget
    }

    // MARK: - Tool Breakdown

    /// Aggregate tool counts across all active sessions, sorted by count descending.
    var toolBreakdown: [(name: String, count: Int)] {
        var merged: [String: Int] = [:]
        for snap in snaps {
            for (name, count) in snap.toolCounts {
                merged[name, default: 0] += count
            }
        }
        return merged.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) }
    }

    /// Total tool invocations across all sessions.
    var totalToolCount: Int {
        toolBreakdown.reduce(0) { $0 + $1.count }
    }
}
