import Foundation
import UserNotifications

final class NotificationManager {

    private let center = UNUserNotificationCenter.current()
    private var isAuthorized = false

    // MARK: - Authorization

    func requestAuthorization() {
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
        guard isAuthorized else { return }

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
