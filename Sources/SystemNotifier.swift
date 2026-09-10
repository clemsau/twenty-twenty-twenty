import Foundation
import UserNotifications

/// Posts the reminder, then deletes it.
///
/// The deletion is the point: a reminder you have already seen has no value
/// sitting in Notification Center, so we remove it shortly after delivery
/// rather than leaving a pile of them to dismiss.
@MainActor
final class SystemNotifier: Notifier {

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Removes every reminder this app has already delivered.
    ///
    /// `notify(withSound:)` schedules its own removal ten seconds after
    /// delivery, but that work lives in an unstructured `Task`: a quit, a
    /// crash, or a forced restart inside that window kills the Task and
    /// orphans the notification in Notification Center forever. Every
    /// delivered notification this app owns is by definition a stale reminder
    /// — the app posts nothing else — so a blanket clear at startup is both
    /// correct and sufficient to keep reminders from being long lived.
    func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }

    func notify(withSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = Twenty.notificationTitle
        content.body = Twenty.notificationBody
        if withSound {
            content.sound = .default
        }

        let id = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        Task {
            try? await center.add(request)
            try? await Task.sleep(for: .seconds(Twenty.notificationRemovalDelay))
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }
    }
}
