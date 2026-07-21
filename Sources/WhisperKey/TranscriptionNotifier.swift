import Foundation
import UserNotifications

enum TranscriptionNotifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                debugLog("notification delivery failed: \(error.localizedDescription)")
            }
        }
    }
}
