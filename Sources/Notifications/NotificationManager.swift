import Foundation
import UserNotifications

final class NotificationManager {

    private var center: UNUserNotificationCenter?
    private var isAuthorized = false

    private func getCenter() -> UNUserNotificationCenter? {
        if center == nil {
            // UNUserNotificationCenter crashes if bundle has no identifier (SwiftPM debug builds)
            guard Bundle.main.bundleIdentifier != nil else {
                return nil
            }
            center = UNUserNotificationCenter.current()
        }
        return center
    }

    // MARK: - Authorization

    func requestAuthorization() {
        guard let center = getCenter() else {
            AppState.log("Notifications unavailable (no bundle identifier)")
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error = error {
                    AppState.log("Notification auth error: \(error.localizedDescription)")
                }
                AppState.log("Notification authorization: \(granted)")
            }
        }
    }

    // MARK: - Send

    func send(title: String, body: String) {
        guard isAuthorized, let center = getCenter() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName("inkpulse_alert.aiff"))

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                AppState.log("Notification send error: \(error.localizedDescription)")
            }
        }
    }
}
