import Foundation
@testable import Twenty_twenty_twenty

@MainActor
final class FakeDateProvider: DateProvider {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
final class SpyNotifier: Notifier {
    private(set) var notifications: [Bool] = []
    var count: Int { notifications.count }

    func notify(withSound: Bool) {
        notifications.append(withSound)
    }
}

@MainActor
final class SpyActivity: ActivityAsserting {
    private(set) var isActive = false
    private(set) var beginCount = 0

    func beginActivity() {
        isActive = true
        beginCount += 1
    }

    func endActivity() {
        isActive = false
    }
}
