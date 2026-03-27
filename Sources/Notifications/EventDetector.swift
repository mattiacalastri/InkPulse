import Foundation

/// Detects significant events from session snapshots and triggers notifications.
final class EventDetector {

    private let notificationManager: NotificationManager
    private var cooldowns: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 60

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    func check(sessions: [String: MetricsSnapshot], sessionCwds: [String: String]) {
        let now = Date()

        for (sessionId, snap) in sessions {
            let project = projectName(
                from: sessionId,
                filePath: nil,
                cwd: sessionCwds[sessionId],
                inferredProject: snap.inferredProject
            )

            // Deploy detected
            if let tool = snap.lastToolName, let target = snap.lastToolTarget {
                if tool == "Bash" && (target.contains("git push") || target.contains("railway")) {
                    notify(key: "\(sessionId):deploy", title: "Deploy", body: "\(project): \(target)", now: now)
                }
            }

            // Error spike (>10%)
            if snap.errorRate > 0.10 {
                notify(key: "\(sessionId):errors", title: "Error Spike", body: "\(project): \(Int(snap.errorRate * 100))% error rate", now: now)
            }

            // Session idle >5min after spending >€0.50
            let idle = now.timeIntervalSince(snap.lastEventTime)
            if idle > 300 && snap.costEUR > 0.5 {
                notify(key: "\(sessionId):idle", title: "Agent Idle", body: "\(project): idle \(Int(idle/60))m (\u{20AC}\(String(format: "%.2f", snap.costEUR)) spent)", now: now)
            }
        }
    }

    private func notify(key: String, title: String, body: String, now: Date) {
        if let expiry = cooldowns[key], now < expiry { return }
        cooldowns[key] = now.addingTimeInterval(cooldownInterval)
        notificationManager.send(title: title, body: body)
        AppState.log("EventDetector: \(title) — \(body)")
    }
}
