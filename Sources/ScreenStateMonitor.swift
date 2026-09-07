import AppKit
import CoreGraphics

/// Reports whether the user can actually see the screen.
///
/// Two mechanisms, because neither covers the whole problem: NSWorkspace
/// notifications catch display and system sleep, while polling the session
/// dictionary catches lock and screensaver, which fire no workspace
/// notification.
///
/// `CGSessionCopyCurrentDictionary` is used in preference to the
/// `com.apple.screenIsLocked` distributed notification because it is public
/// API, works under the App Sandbox, and carries no App Store review risk.
@MainActor
final class ScreenStateMonitor {

    private(set) var state: ScreenState = .active
    var onChange: ((ScreenState) -> Void)?

    private var displayAsleep = false

    init() {
        let center = NSWorkspace.shared.notificationCenter
        let asleep: [NSNotification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ]
        let awake: [NSNotification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
        ]

        for name in asleep {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setDisplayAsleep(true) }
            }
        }
        for name in awake {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setDisplayAsleep(false) }
            }
        }

        state = currentState()
    }

    /// Called from the app's existing one-second tick, so lock detection
    /// rides along for free rather than needing a timer of its own.
    func poll() {
        update(to: currentState())
    }

    // MARK: - Private

    private func setDisplayAsleep(_ value: Bool) {
        displayAsleep = value
        update(to: currentState())
    }

    private func currentState() -> ScreenState {
        (displayAsleep || isSessionLocked()) ? .inactive : .active
    }

    private func update(to newValue: ScreenState) {
        guard newValue != state else { return }
        state = newValue
        onChange?(newValue)
    }

    private func isSessionLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as NSDictionary? as? [String: Any] else {
            // No session dictionary means no logged-in GUI session to speak
            // of; treat it as "not visible" rather than guessing.
            return true
        }
        let locked = info["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = info["kCGSSessionOnConsoleKey"] as? Bool ?? true
        return locked || !onConsole
    }
}
