import Foundation
import AppKit
import UserNotifications

/// Sends macOS notifications when a gate window appears.
class GateNotification: NSObject, UNUserNotificationCenterDelegate {
    static let shared = GateNotification()

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    /// Request notification permission (called once at startup).
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                FileHandle.standardError.write(Data("claude-gate: Notification permission error: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    /// Send a notification that a gate requires attention.
    func notify(ruleName: String, riskLevel: String, command: String) {
        let content = UNMutableNotificationContent()
        content.title = "claude-gate: Authorization Required"
        content.subtitle = "\(ruleName) (\(riskLevel.uppercased()))"

        // Truncate command for notification body
        let shortCmd = command.count > 100 ? String(command.prefix(97)) + "..." : command
        content.body = shortCmd
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "gate-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                FileHandle.standardError.write(Data("claude-gate: Failed to send notification: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification tap — bring the app to front.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        completionHandler()
    }

    /// Show notifications even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
