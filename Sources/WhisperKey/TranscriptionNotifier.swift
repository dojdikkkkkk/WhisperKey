import Foundation
import UserNotifications

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum TranscriptionNotifier {
    private static let delegate = NotificationDelegate()

    private static var center: UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        return center
    }

    static func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                debugLog("notification permission failed: \(error.localizedDescription)")
            }
        }
    }

    static func postCloudFailure(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Cloud transcription failed"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                debugLog("notification delivery failed: \(error.localizedDescription)")
            }
        }
    }
}
