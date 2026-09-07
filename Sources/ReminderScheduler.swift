import Foundation

/// The 20-20-20 state machine.
///
/// Deliberately free of AppKit and UserNotifications so it can be driven by a
/// fake clock in tests without waiting on real time.
@MainActor
final class ReminderScheduler {

    enum State: Equatable {
        case disabled
        case counting(deadline: Date)
        case suspended
    }

    private(set) var state: State = .disabled
    var soundEnabled = true

    private let dateProvider: any DateProvider
    private let notifier: any Notifier
    private let activity: any ActivityAsserting
    private var screenState: ScreenState = .active

    init(dateProvider: any DateProvider, notifier: any Notifier, activity: any ActivityAsserting) {
        self.dateProvider = dateProvider
        self.notifier = notifier
        self.activity = activity
    }

    var isEnabled: Bool {
        state != .disabled
    }

    /// Whole seconds until the next reminder, or nil when not counting.
    var secondsRemaining: Int? {
        guard case .counting(let deadline) = state else { return nil }
        return max(0, Int(deadline.timeIntervalSince(dateProvider.now).rounded(.up)))
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        transition(to: enabled ? startedState() : .disabled)
    }

    func screenStateChanged(to newValue: ScreenState) {
        guard newValue != screenState else { return }
        screenState = newValue
        guard isEnabled else { return }
        transition(to: newValue == .active ? startedState() : .suspended)
    }

    /// Called once per second. Compares an absolute deadline against the
    /// current time, so a missed tick or a clock jump self-corrects rather
    /// than accumulating drift.
    func tick() {
        guard case .counting(let deadline) = state else { return }
        guard dateProvider.now >= deadline else { return }
        notifier.notify(withSound: soundEnabled)
        state = .counting(deadline: dateProvider.now.addingTimeInterval(Twenty.interval))
    }

    // MARK: - Private

    /// The state to enter when reminders are on: counting if the user is at
    /// the screen, suspended otherwise.
    private func startedState() -> State {
        screenState == .active
            ? .counting(deadline: dateProvider.now.addingTimeInterval(Twenty.interval))
            : .suspended
    }

    private func transition(to newState: State) {
        state = newState
        if case .counting = newState {
            activity.beginActivity()
        } else {
            activity.endActivity()
        }
    }
}
