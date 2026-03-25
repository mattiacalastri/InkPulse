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
}
