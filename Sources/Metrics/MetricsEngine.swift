import Foundation
import Combine

// MARK: - MetricsSnapshot

struct MetricsSnapshot {
    let sessionId: String
    let model: String
    let tokenMin: Double
    let toolFreq: Double
    let idleAvgS: Double
    let errorRate: Double
    let thinkOutputRatio: Double?
    let cacheHit: Double
    let subagentCount: Int
    let costEUR: Double
    let health: Int
    let anomaly: String?
    let startTime: Date
    let lastEventTime: Date
    let egiState: EGIState
    let egiConfidence: Double
    let toolDiversity: Int
    let domainSpread: Int

    // Feature 1: Context Window %
    let lastContextTokens: Int
    let contextPercent: Double  // 0.0 - 1.0+

    // Feature 2: Last Tool + Task Name
    let lastToolName: String?
    let lastToolTarget: String?
    let activeTaskName: String?

    // Project inference (when cwd is Home)
    let inferredProject: String?

    // Cumulative tool invocation counts by name
    let toolCounts: [String: Int]
}

// MARK: - MetricsEngine

final class MetricsEngine: ObservableObject {

    @Published var sessions: [String: MetricsSnapshot] = [:]

    /// Internal per-session state trackers.
    private(set) var sessionTrackers: [String: SessionMetrics] = [:]

    var trackerCount: Int { sessionTrackers.count }

    private let timeoutSeconds: Double

    init(timeoutSeconds: Double = Double(InkPulseDefaults.sessionTimeoutSeconds)) {
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Ingest

    func ingest(_ event: ClaudeEvent) {
        guard let sessionId = event.sessionId, let ts = event.timestamp else { return }

        if sessionTrackers[sessionId] == nil {
            sessionTrackers[sessionId] = SessionMetrics(sessionId: sessionId, startTime: ts)
        }

        sessionTrackers[sessionId]?.ingest(event)
    }

    // MARK: - Refresh

    func refreshSnapshots(at now: Date = Date()) {
        var updated: [String: MetricsSnapshot] = [:]

        for (id, tracker) in sessionTrackers {
            // Remove sessions inactive > timeout
            if now.timeIntervalSince(tracker.lastEventTime) > timeoutSeconds {
                continue
            }
            updated[id] = tracker.snapshot(at: now)
        }

        // Clean up removed trackers
        let activeIds = Set(updated.keys)
        for id in sessionTrackers.keys where !activeIds.contains(id) {
            sessionTrackers.removeValue(forKey: id)
        }

        sessions = updated
    }

    // MARK: - Aggregates

    /// Average health across active sessions, or -1 if no sessions.
    var aggregateHealth: Int {
        let snapshots = Array(sessions.values)
        if snapshots.isEmpty { return -1 }
        let sum = snapshots.reduce(0) { $0 + $1.health }
        return sum / snapshots.count
    }

    /// Most severe anomaly across all active sessions, or nil.
    var primaryAnomaly: Anomaly? {
        sessions.values
            .compactMap { snap -> Anomaly? in
                guard let raw = snap.anomaly else { return nil }
                return Anomaly(rawValue: raw)
            }
            .max { $0.severity < $1.severity }
    }

    /// Highest EGI state across all active sessions.
    var globalEGIState: EGIState {
        sessions.values.map(\.egiState).max() ?? .dormant
    }

    /// Number of sessions with EGI state above dormant.
    var egiWindowCount: Int {
        sessions.values.filter { $0.egiState > .dormant }.count
    }
}
