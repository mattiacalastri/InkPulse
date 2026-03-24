import Foundation

final class AnomalyWatcher {

    private let notificationManager: NotificationManager

    static let criticalAnomalies: Set<Anomaly> = [.hemorrhage, .explosion, .loop]

    private var previousState: [String: Anomaly] = [:]
    private var cooldowns: [String: Date] = [:]
    private var lastGlobalNotification: Date = .distantPast

    private let perSessionCooldown: TimeInterval = 300   // 5 minutes
    private let globalCooldown: TimeInterval = 30        // 30 seconds

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    // MARK: - Check

    func check(sessions: [String: MetricsSnapshot], sessionCwds: [String: String]) {
        let now = Date()

        for (sessionId, snapshot) in sessions {
            let currentAnomaly: Anomaly? = snapshot.anomaly.flatMap { Anomaly(rawValue: $0) }
            let previousAnomaly: Anomaly? = previousState[sessionId]

            if let anomaly = currentAnomaly,
               Self.criticalAnomalies.contains(anomaly),
               previousAnomaly == nil {

                let cooldownKey = "\(sessionId):\(anomaly.rawValue)"

                if let expiry = cooldowns[cooldownKey], now < expiry {
                    previousState[sessionId] = currentAnomaly
                    continue
                }

                if now.timeIntervalSince(lastGlobalNotification) < globalCooldown {
                    previousState[sessionId] = currentAnomaly
                    continue
                }

                let project = projectName(
                    from: sessionId,
                    filePath: nil,
                    cwd: sessionCwds[sessionId]
                )

                notificationManager.send(
                    title: anomaly.notificationTitle,
                    body: anomaly.notificationBody(project: project, snapshot: snapshot)
                )

                cooldowns[cooldownKey] = now.addingTimeInterval(perSessionCooldown)
                lastGlobalNotification = now
            }

            previousState[sessionId] = currentAnomaly
        }

        // Clean up stale entries
        let activeIds = Set(sessions.keys)
        for id in previousState.keys where !activeIds.contains(id) {
            previousState.removeValue(forKey: id)
        }
    }
}
