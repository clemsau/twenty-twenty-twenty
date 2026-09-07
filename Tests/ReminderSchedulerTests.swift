import Foundation
import Testing
@testable import Twenty_twenty_twenty

@MainActor
@Suite("ReminderScheduler")
struct ReminderSchedulerTests {

    /// Builds a scheduler already counting down, which is the starting point
    /// for most of these cases.
    private func makeCounting() -> (ReminderScheduler, FakeDateProvider, SpyNotifier, SpyActivity) {
        let clock = FakeDateProvider()
        let notifier = SpyNotifier()
        let activity = SpyActivity()
        let scheduler = ReminderScheduler(dateProvider: clock, notifier: notifier, activity: activity)
        scheduler.setEnabled(true)
        return (scheduler, clock, notifier, activity)
    }

    @Test("Starts disabled")
    func startsDisabled() {
        let clock = FakeDateProvider()
        let scheduler = ReminderScheduler(
            dateProvider: clock, notifier: SpyNotifier(), activity: SpyActivity()
        )
        #expect(scheduler.state == .disabled)
        #expect(scheduler.secondsRemaining == nil)
    }

    @Test("Enabling while the screen is active starts a full countdown")
    func enableStartsCountdown() {
        let (scheduler, clock, _, _) = makeCounting()
        #expect(scheduler.state == .counting(deadline: clock.now.addingTimeInterval(1200)))
        #expect(scheduler.secondsRemaining == 1200)
    }

    @Test("Enabling while the screen is locked goes straight to suspended")
    func enableWhileLocked() {
        let clock = FakeDateProvider()
        let scheduler = ReminderScheduler(
            dateProvider: clock, notifier: SpyNotifier(), activity: SpyActivity()
        )
        scheduler.screenStateChanged(to: .inactive)
        scheduler.setEnabled(true)
        #expect(scheduler.state == .suspended)
        #expect(scheduler.secondsRemaining == nil)
    }

    @Test("Does not fire before the deadline")
    func noEarlyFire() {
        let (scheduler, clock, notifier, _) = makeCounting()
        clock.advance(by: 1199)
        scheduler.tick()
        #expect(notifier.count == 0)
        #expect(scheduler.secondsRemaining == 1)
    }

    @Test("Fires at twenty minutes and reschedules for another twenty")
    func firesAndReschedules() {
        let (scheduler, clock, notifier, _) = makeCounting()
        clock.advance(by: 1200)
        scheduler.tick()
        #expect(notifier.count == 1)
        #expect(scheduler.state == .counting(deadline: clock.now.addingTimeInterval(1200)))

        clock.advance(by: 1200)
        scheduler.tick()
        #expect(notifier.count == 2)
    }

    @Test("Passes the sound preference through to the notifier")
    func soundPreference() {
        let (scheduler, clock, notifier, _) = makeCounting()
        scheduler.soundEnabled = false
        clock.advance(by: 1200)
        scheduler.tick()
        #expect(notifier.notifications == [false])
    }

    @Test("Screen sleeping mid-count suspends and cancels the deadline")
    func sleepSuspends() {
        let (scheduler, clock, notifier, _) = makeCounting()
        clock.advance(by: 600)
        scheduler.screenStateChanged(to: .inactive)
        #expect(scheduler.state == .suspended)

        // Hours pass with the lid shut; nothing should queue up.
        clock.advance(by: 7200)
        scheduler.tick()
        #expect(notifier.count == 0)
    }

    @Test("Waking restarts from a full twenty minutes, not from where it stopped")
    func wakeRestartsFresh() {
        let (scheduler, clock, notifier, _) = makeCounting()
        clock.advance(by: 1199)
        scheduler.screenStateChanged(to: .inactive)
        clock.advance(by: 60)
        scheduler.screenStateChanged(to: .active)

        #expect(scheduler.secondsRemaining == 1200)
        scheduler.tick()
        #expect(notifier.count == 0)
    }

    @Test("Waking while disabled stays disabled")
    func wakeWhileDisabled() {
        let clock = FakeDateProvider()
        let scheduler = ReminderScheduler(
            dateProvider: clock, notifier: SpyNotifier(), activity: SpyActivity()
        )
        scheduler.screenStateChanged(to: .inactive)
        scheduler.screenStateChanged(to: .active)
        #expect(scheduler.state == .disabled)
    }

    @Test("Disabling mid-count clears the deadline")
    func disableClears() {
        let (scheduler, clock, notifier, _) = makeCounting()
        clock.advance(by: 600)
        scheduler.setEnabled(false)
        #expect(scheduler.state == .disabled)

        clock.advance(by: 7200)
        scheduler.tick()
        #expect(notifier.count == 0)
    }

    @Test("A forward clock jump fires once, not once per missed interval")
    func clockJumpFiresOnce() {
        let (scheduler, clock, notifier, _) = makeCounting()
        clock.advance(by: 7200)  // two hours in one step
        scheduler.tick()
        #expect(notifier.count == 1)
        #expect(scheduler.secondsRemaining == 1200)
    }

    @Test("Holds the App Nap assertion only while counting")
    func activityLifecycle() {
        let (scheduler, _, _, activity) = makeCounting()
        #expect(activity.isActive)

        scheduler.screenStateChanged(to: .inactive)
        #expect(!activity.isActive)

        scheduler.screenStateChanged(to: .active)
        #expect(activity.isActive)

        scheduler.setEnabled(false)
        #expect(!activity.isActive)
    }

    @Test("Enabling twice does not stack activity assertions")
    func idempotentEnable() {
        let (scheduler, _, _, activity) = makeCounting()
        scheduler.setEnabled(true)
        #expect(activity.beginCount == 1)
    }

    @Test("Redundant active notification does not reset the in-flight countdown")
    func redundantActiveDoesNotResetCountdown() {
        let (scheduler, clock, _, _) = makeCounting()
        clock.advance(by: 600)
        // Screen was already active; delivering active again must be a no-op.
        scheduler.screenStateChanged(to: .active)
        #expect(scheduler.secondsRemaining == 600)
    }
}
