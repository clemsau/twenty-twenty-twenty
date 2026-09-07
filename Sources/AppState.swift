import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {

    private enum Key {
        static let remindersEnabled = "remindersEnabled"
        static let soundEnabled = "soundEnabled"
    }

    // MARK: - Bound by the popover

    var remindersEnabled = false {
        didSet {
            guard oldValue != remindersEnabled else { return }
            defaults.set(remindersEnabled, forKey: Key.remindersEnabled)
            if remindersEnabled {
                Task { await enableAfterAuthorization() }
            } else {
                scheduler.setEnabled(false)
                refreshStatus()
            }
        }
    }

    var soundEnabled = true {
        didSet {
            // Skip side effects while restoring persisted state at launch.
            guard !isSyncingFromSystem else { return }
            guard oldValue != soundEnabled else { return }
            defaults.set(soundEnabled, forKey: Key.soundEnabled)
            scheduler.soundEnabled = soundEnabled
        }
    }

    var launchAtLogin = false {
        didSet {
            // Skip SMAppService calls when the write only mirrors the system.
            guard !isSyncingFromSystem else { return }
            guard oldValue != launchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }

    private(set) var statusText: String?
    private(set) var permissionDenied = false

    // MARK: - Private

    private let defaults = UserDefaults.standard
    private let notifier = SystemNotifier()
    private let monitor = ScreenStateMonitor()
    private let scheduler: ReminderScheduler
    private var timer: Timer?

    /// True while we are writing a property to mirror what the system already
    /// reports, rather than to enact a user's choice. Prevents `didSet`
    /// observers from firing their persistence/registration side effects.
    /// Set during the `start()` loading phase and during the corrective
    /// write-back in `applyLaunchAtLogin()`.
    ///
    /// This matters more than it looks: under `@Observable` the stored
    /// properties become computed, so assigning inside a `didSet` re-enters
    /// that same `didSet` instead of being skipped as it would for a plain
    /// stored property.
    private var isSyncingFromSystem = false

    init() {
        scheduler = ReminderScheduler(
            dateProvider: SystemDateProvider(),
            notifier: notifier,
            activity: ProcessInfoActivity()
        )
    }

    func start() {
        // A MenuBarExtra's content view is torn down and rebuilt every time the
        // menu opens, so start() can be called repeatedly. Without this guard a
        // second call would add another RunLoop timer — the old one keeps
        // firing because the RunLoop, not us, owns it — and the countdown would
        // burn a second per tick per timer.
        guard timer == nil else { return }

        isSyncingFromSystem = true

        // Restore soundEnabled without triggering the UserDefaults write or
        // scheduler update in didSet. We sync the scheduler manually below.
        soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        scheduler.soundEnabled = soundEnabled

        // Restore launchAtLogin without triggering SMAppService.register().
        launchAtLogin = SMAppService.mainApp.status == .enabled

        isSyncingFromSystem = false

        monitor.onChange = { [weak self] newState in
            self?.scheduler.screenStateChanged(to: newState)
            self?.refreshStatus()
        }
        scheduler.screenStateChanged(to: monitor.state)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common so the countdown keeps ticking while the popover is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Restore remindersEnabled AFTER isSyncingFromSystem is false so its didSet
        // fires normally. A user who had reminders on expects them running
        // after a restart — the scheduler start and optional authorization
        // request are intentional on this property alone.
        remindersEnabled = defaults.object(forKey: Key.remindersEnabled) as? Bool ?? false
        refreshStatus()
    }

    func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    private func tick() {
        monitor.poll()
        scheduler.tick()
        refreshStatus()
    }

    /// Ask for permission on first enable rather than at launch, so the
    /// system prompt appears with obvious context.
    private func enableAfterAuthorization() async {
        let status = await notifier.authorizationStatus()
        let granted: Bool
        switch status {
        case .notDetermined:
            granted = await notifier.requestAuthorization()
        case .denied:
            granted = false
        default:
            granted = true
        }

        // Record the authorization fact first: the banner it drives describes
        // the system, not the toggle, so it must not be left stale.
        permissionDenied = !granted

        // The prompt is modal and slow; the user may have toggled reminders
        // back off while it was up. Do not act on that stale intent.
        guard remindersEnabled else { return }

        guard granted else {
            remindersEnabled = false
            return
        }
        scheduler.setEnabled(true)
        refreshStatus()
    }

    private func refreshStatus() {
        guard scheduler.isEnabled else {
            statusText = nil
            return
        }
        guard let seconds = scheduler.secondsRemaining else {
            statusText = "Paused — screen off"
            return
        }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        statusText = minutes <= 1 ? "Next break in under a minute" : "Next break in \(minutes) min"
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The registration failed (most often because the app is not in
            // /Applications); reflect reality rather than lying in the UI.
            // Suppress the observer: under @Observable this assignment would
            // otherwise re-enter launchAtLogin's didSet and call back into here
            // with the corrected value, issuing an unregister() for the service
            // the user just asked us to register.
            isSyncingFromSystem = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isSyncingFromSystem = false
        }
    }
}
