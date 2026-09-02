import Foundation

enum Twenty {
    /// The 20-minute gap between reminders. Not configurable by design.
    static let interval: TimeInterval = 20 * 60

    /// How long a delivered notification lingers before we delete it from
    /// Notification Center. A past reminder has no review value.
    static let notificationRemovalDelay: TimeInterval = 10

    static let notificationTitle = "Look away"
    static let notificationBody = "Focus on something 20 feet away for 20 seconds."
}
