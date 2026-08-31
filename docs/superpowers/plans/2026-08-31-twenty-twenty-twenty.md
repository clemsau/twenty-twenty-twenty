# Twenty twenty twenty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A minimalist macOS menu bar app that posts a notification every 20 minutes while the user is at the screen, reminding them to look 20 feet away for 20 seconds, and leaves no trace in Notification Center.

**Architecture:** A pure-logic `ReminderScheduler` state machine (disabled / counting / suspended) driven by a 1-second tick, with all system interaction behind three small protocols (`DateProvider`, `Notifier`, `ActivityAsserting`) so the scheduler is tested with a fake clock and no real waiting. A SwiftUI `MenuBarExtra` with `LSUIElement` provides the entire UI — no dock icon, no main window.

**Tech Stack:** Swift 6.2, SwiftUI, `MenuBarExtra`, UserNotifications, ServiceManagement (`SMAppService`), CoreGraphics (`CGSessionCopyCurrentDictionary`), Swift Testing, XcodeGen, Homebrew cask.

**Spec:** `docs/superpowers/specs/2026-08-31-twenty-twenty-twenty-design.md`

## Global Constraints

- **Deployment target:** macOS 14.0 (Sonoma). Set in `project.yml` as `deploymentTarget: "14.0"`.
- **Bundle identifier:** `com.clementsauvage.TwentyTwentyTwenty`
- **Product name:** `Twenty twenty twenty` (with spaces — this is the `.app` filename users see). The Xcode *target* is named `TwentyTwentyTwenty` (no spaces).
- **Reminder interval:** exactly `20 * 60` seconds. Not configurable, not exposed in UI.
- **Notification removal delay:** exactly `10` seconds after posting.
- **Notification copy:** title `"Look away"`, body `"Focus on something 20 feet away for 20 seconds."` — verbatim.
- **No dock icon:** `LSUIElement = true` in Info.plist. Never add a `WindowGroup`.
- **App Sandbox enabled** from the first commit. No entitlements beyond the sandbox default.
- **No private APIs.** Lock detection uses `CGSessionCopyCurrentDictionary()`, never the `com.apple.screenIsLocked` distributed notification.
- **Swift language mode 6.** All UI and system-touching types are `@MainActor`.
- **No third-party runtime dependencies.** XcodeGen is a build-time tool only.
- Never accumulate elapsed time. Always compare an absolute deadline against `dateProvider.now`.

## File Structure

| File | Responsibility |
|---|---|
| `project.yml` | XcodeGen definition; regenerates `TwentyTwentyTwenty.xcodeproj` |
| `Sources/Constants.swift` | The three magic numbers and the notification copy |
| `Sources/DateProvider.swift` | `DateProvider` protocol + `SystemDateProvider` |
| `Sources/Notifier.swift` | `Notifier` protocol (no implementation) |
| `Sources/ActivityAsserting.swift` | `ActivityAsserting` protocol + `ProcessInfoActivity` |
| `Sources/ScreenState.swift` | `ScreenState` enum |
| `Sources/ReminderScheduler.swift` | The state machine. Pure Foundation, no AppKit |
| `Sources/ScreenStateMonitor.swift` | NSWorkspace sleep/wake + CGSession lock polling |
| `Sources/SystemNotifier.swift` | `UNUserNotificationCenter` wrapper with auto-removal |
| `Sources/AppState.swift` | `@Observable` state, `UserDefaults`, `SMAppService`, the 1s timer |
| `Sources/PopoverView.swift` | The popover UI |
| `Sources/TwentyTwentyTwentyApp.swift` | `@main`, `MenuBarExtra` |
| `Sources/Info.plist` | `LSUIElement` |
| `Sources/TwentyTwentyTwenty.entitlements` | Sandbox |
| `Sources/Assets.xcassets/` | App icon + menu bar template images |
| `Tools/GenerateIcons.swift` | Draws all icon assets from code; run manually |
| `Tests/ReminderSchedulerTests.swift` | The only substantial test suite |
| `Tests/Fakes.swift` | `FakeDateProvider`, `SpyNotifier`, `SpyActivity` |
| `Makefile` | build, test, dmg |
| `Casks/twenty-twenty-twenty.rb` | Homebrew cask |
| `README.md` | Install instructions incl. the `--no-quarantine` caveat |

---

### Task 1: Project scaffold that builds and tests

**Files:**
- Create: `project.yml`
- Create: `Sources/Constants.swift`
- Create: `Sources/Info.plist`
- Create: `Sources/TwentyTwentyTwenty.entitlements`
- Create: `Sources/TwentyTwentyTwentyApp.swift`
- Create: `Makefile`
- Test: `Tests/ConstantsTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum Twenty { static let interval: TimeInterval; static let notificationRemovalDelay: TimeInterval; static let notificationTitle: String; static let notificationBody: String }`; an `xcodebuild test -scheme TwentyTwentyTwenty` that passes.

- [ ] **Step 1: Install XcodeGen**

```bash
brew install xcodegen
xcodegen --version
```

- [ ] **Step 2: Write `project.yml`**

```yaml
name: TwentyTwentyTwenty
options:
  bundleIdPrefix: com.clementsauvage
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""

targets:
  TwentyTwentyTwenty:
    type: application
    platform: macOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_NAME: "Twenty twenty twenty"
        PRODUCT_BUNDLE_IDENTIFIER: com.clementsauvage.TwentyTwentyTwenty
        INFOPLIST_FILE: Sources/Info.plist
        CODE_SIGN_ENTITLEMENTS: Sources/TwentyTwentyTwenty.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        ENABLE_APP_SANDBOX: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        COMBINE_HIDPI_IMAGES: YES

  TwentyTwentyTwentyTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: TwentyTwentyTwenty

schemes:
  TwentyTwentyTwenty:
    build:
      targets:
        TwentyTwentyTwenty: all
        TwentyTwentyTwentyTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - TwentyTwentyTwentyTests
```

- [ ] **Step 3: Write `Sources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string></string>
</dict>
</plist>
```

- [ ] **Step 4: Write `Sources/TwentyTwentyTwenty.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 5: Write the failing test**

Create `Tests/ConstantsTests.swift`:

```swift
import Testing
@testable import Twenty_twenty_twenty

@Suite("Constants")
struct ConstantsTests {
    @Test("Reminder interval is exactly twenty minutes")
    func interval() {
        #expect(Twenty.interval == 1200)
    }

    @Test("Notifications are removed ten seconds after posting")
    func removalDelay() {
        #expect(Twenty.notificationRemovalDelay == 10)
    }
}
```

Note: the Swift module name is derived from `PRODUCT_NAME`, so spaces become
underscores — the import is `Twenty_twenty_twenty`. If the build disagrees,
read the actual `PRODUCT_MODULE_NAME` from
`xcodebuild -showBuildSettings -scheme TwentyTwentyTwenty | grep PRODUCT_MODULE_NAME`
and use that.

- [ ] **Step 6: Write a minimal app entry point so the target links**

Create `Sources/TwentyTwentyTwentyApp.swift`:

```swift
import SwiftUI

@main
struct TwentyTwentyTwentyApp: App {
    var body: some Scene {
        MenuBarExtra("Twenty twenty twenty", systemImage: "eye") {
            Text("Placeholder")
        }
        .menuBarExtraStyle(.window)
    }
}
```

This entry point is replaced wholesale in Task 6. It exists now only so the
app target has a `@main` and can link.

- [ ] **Step 7: Generate the project and run the test to verify it fails**

```bash
xcodegen generate
xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: FAIL — `cannot find 'Twenty' in scope`.

- [ ] **Step 8: Write `Sources/Constants.swift`**

```swift
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
```

- [ ] **Step 9: Run tests to verify they pass**

```bash
xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: PASS, 2 tests.

- [ ] **Step 10: Write the `Makefile`**

```makefile
SCHEME  := TwentyTwentyTwenty
APP     := Twenty twenty twenty
BUILD   := build
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
             "$(BUILD)/$(APP).app/Contents/Info.plist" 2>/dev/null || echo 1.0.0)

.PHONY: project test build dmg clean

project:
	xcodegen generate

test: project
	xcodebuild test -scheme $(SCHEME) -destination 'platform=macOS'

build: project
	xcodebuild -scheme $(SCHEME) -configuration Release \
	  CONFIGURATION_BUILD_DIR=$(CURDIR)/$(BUILD) build

dmg: build
	rm -rf $(BUILD)/dmg $(BUILD)/$(SCHEME).dmg
	mkdir -p $(BUILD)/dmg
	cp -R "$(BUILD)/$(APP).app" $(BUILD)/dmg/
	ln -s /Applications $(BUILD)/dmg/Applications
	hdiutil create -volname "$(APP)" -srcfolder $(BUILD)/dmg \
	  -ov -format UDZO $(BUILD)/$(SCHEME).dmg
	shasum -a 256 $(BUILD)/$(SCHEME).dmg

clean:
	rm -rf $(BUILD) $(SCHEME).xcodeproj
```

- [ ] **Step 11: Ignore generated artefacts**

Append to `.gitignore`:

```
TwentyTwentyTwenty.xcodeproj/
*.xcworkspace
```

The `.xcodeproj` is generated from `project.yml`, so it is not committed.

- [ ] **Step 12: Commit**

```bash
git add project.yml Makefile .gitignore Sources Tests
git commit -m "Add project scaffold with XcodeGen, sandbox, and LSUIElement

The .xcodeproj is generated rather than committed so the project
definition stays reviewable in project.yml."
```

---

### Task 2: ReminderScheduler state machine

The heart of the app, and the only file with logic worth testing. Pure
Foundation — do not import AppKit or SwiftUI here.

**Files:**
- Create: `Sources/DateProvider.swift`
- Create: `Sources/Notifier.swift`
- Create: `Sources/ActivityAsserting.swift`
- Create: `Sources/ScreenState.swift`
- Create: `Sources/ReminderScheduler.swift`
- Test: `Tests/Fakes.swift`
- Test: `Tests/ReminderSchedulerTests.swift`

**Interfaces:**
- Consumes: `Twenty.interval` from Task 1.
- Produces:
  - `protocol DateProvider { var now: Date { get } }`, `struct SystemDateProvider: DateProvider`
  - `protocol Notifier: AnyObject { func notify(withSound: Bool) }`
  - `protocol ActivityAsserting: AnyObject { func beginActivity(); func endActivity() }`, `final class ProcessInfoActivity: ActivityAsserting`
  - `enum ScreenState { case active, inactive }`
  - `final class ReminderScheduler` with `init(dateProvider:notifier:activity:)`, `var soundEnabled: Bool`, `private(set) var state: State`, `func setEnabled(_:)`, `func screenStateChanged(to:)`, `func tick()`, `var secondsRemaining: Int?`, `var isEnabled: Bool`
  - `enum ReminderScheduler.State: Equatable { case disabled, counting(deadline: Date), suspended }`

- [ ] **Step 1: Write the protocol files**

`Sources/DateProvider.swift`:

```swift
import Foundation

@MainActor
protocol DateProvider {
    var now: Date { get }
}

@MainActor
struct SystemDateProvider: DateProvider {
    var now: Date { Date() }
}
```

`Sources/Notifier.swift`:

```swift
import Foundation

@MainActor
protocol Notifier: AnyObject {
    func notify(withSound: Bool)
}
```

`Sources/ScreenState.swift`:

```swift
enum ScreenState {
    case active
    case inactive
}
```

`Sources/ActivityAsserting.swift`:

```swift
import Foundation

/// Holds a power-management assertion that exempts us from App Nap.
///
/// Without this, macOS coalesces our timer and a "20 minute" reminder can
/// arrive minutes late. `.userInitiatedAllowingIdleSystemSleep` opts out of
/// App Nap while still letting the Mac sleep normally — which we want, since
/// a sleeping Mac means the user is not looking at the screen.
@MainActor
protocol ActivityAsserting: AnyObject {
    func beginActivity()
    func endActivity()
}

@MainActor
final class ProcessInfoActivity: ActivityAsserting {
    private var token: (any NSObjectProtocol)?

    func beginActivity() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "20-20-20 reminder timer"
        )
    }

    func endActivity() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}
```

- [ ] **Step 2: Write the test fakes**

`Tests/Fakes.swift`:

```swift
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
```

- [ ] **Step 3: Write the failing tests**

`Tests/ReminderSchedulerTests.swift`:

```swift
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
}
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: FAIL — `cannot find 'ReminderScheduler' in scope`.

- [ ] **Step 5: Write `Sources/ReminderScheduler.swift`**

```swift
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
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: PASS, 15 tests.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "Add ReminderScheduler state machine with fake-clock tests

Deadline-based rather than accumulating, so a missed tick or a system
clock jump self-corrects instead of drifting or double-firing."
```

---

### Task 3: ScreenStateMonitor

**Files:**
- Create: `Sources/ScreenStateMonitor.swift`

**Interfaces:**
- Consumes: `ScreenState` from Task 2.
- Produces: `final class ScreenStateMonitor` with `init()`, `var onChange: ((ScreenState) -> Void)?`, `private(set) var state: ScreenState`, `func poll()`.

No unit tests: this is a thin wrapper over Apple APIs whose behaviour cannot be
faked without mocking the frameworks themselves. It is verified by hand in
Task 8.

- [ ] **Step 1: Write `Sources/ScreenStateMonitor.swift`**

```swift
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
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            // No session dictionary means no logged-in GUI session to speak
            // of; treat it as "not visible" rather than guessing.
            return true
        }
        let locked = info["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = info["kCGSSessionOnConsoleKey"] as? Bool ?? true
        return locked || !onConsole
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
xcodegen generate && xcodebuild build -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

If `CGSessionCopyCurrentDictionary() as? [String: Any]` fails to compile,
bridge explicitly: `CGSessionCopyCurrentDictionary() as NSDictionary? as? [String: Any]`.

- [ ] **Step 3: Run the existing tests to confirm nothing regressed**

```bash
xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: PASS, 15 tests.

- [ ] **Step 4: Commit**

```bash
git add Sources/ScreenStateMonitor.swift
git commit -m "Add ScreenStateMonitor using public session-dictionary polling

Combines NSWorkspace sleep/wake notifications with CGSession polling for
lock and screensaver, which fire no workspace notification."
```

---

### Task 4: SystemNotifier

**Files:**
- Create: `Sources/SystemNotifier.swift`

**Interfaces:**
- Consumes: `Notifier` protocol, `Twenty.notificationTitle`, `Twenty.notificationBody`, `Twenty.notificationRemovalDelay`.
- Produces: `final class SystemNotifier: Notifier` with `func requestAuthorization() async -> Bool`, `func authorizationStatus() async -> UNAuthorizationStatus`, `func notify(withSound: Bool)`.

Also a thin wrapper; verified by hand in Task 8.

- [ ] **Step 1: Write `Sources/SystemNotifier.swift`**

```swift
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
```

- [ ] **Step 2: Verify it compiles and tests still pass**

```bash
xcodegen generate && xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`, 15 tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/SystemNotifier.swift
git commit -m "Add SystemNotifier that removes delivered reminders after 10s

A reminder you have already seen has no value in Notification Center."
```

---

### Task 5: AppState — persistence, login item, and the tick

Wires the previous four tasks together and exposes exactly what the popover
binds to.

**Files:**
- Create: `Sources/AppState.swift`

**Interfaces:**
- Consumes: `ReminderScheduler`, `ScreenStateMonitor`, `SystemNotifier`, `SystemDateProvider`, `ProcessInfoActivity`, `Twenty`.
- Produces: `@Observable @MainActor final class AppState` with:
  - `var remindersEnabled: Bool` (settable; persisted)
  - `var soundEnabled: Bool` (settable; persisted)
  - `var launchAtLogin: Bool` (settable; mirrored to `SMAppService`)
  - `private(set) var statusText: String?` — the popover's dimmed line, nil when disabled
  - `private(set) var permissionDenied: Bool`
  - `func start()`
  - `func openNotificationSettings()`

- [ ] **Step 1: Write `Sources/AppState.swift`**

```swift
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
            guard oldValue != soundEnabled else { return }
            defaults.set(soundEnabled, forKey: Key.soundEnabled)
            scheduler.soundEnabled = soundEnabled
        }
    }

    var launchAtLogin = false {
        didSet {
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

    init() {
        scheduler = ReminderScheduler(
            dateProvider: SystemDateProvider(),
            notifier: notifier,
            activity: ProcessInfoActivity()
        )
    }

    func start() {
        soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        scheduler.soundEnabled = soundEnabled
        launchAtLogin = SMAppService.mainApp.status == .enabled

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

        permissionDenied = !granted
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
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

- [ ] **Step 2: Verify it compiles and tests still pass**

```bash
xcodegen generate && xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`, 15 tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/AppState.swift
git commit -m "Add AppState wiring scheduler, screen monitor, and preferences

Notification permission is requested on first enable rather than at
launch so the system prompt arrives with context."
```

---

### Task 6: The popover

**Files:**
- Create: `Sources/PopoverView.swift`
- Modify: `Sources/TwentyTwentyTwentyApp.swift` (replace the Task 1 placeholder entirely)

**Interfaces:**
- Consumes: `AppState` from Task 5.
- Produces: `struct PopoverView: View` taking `@Bindable var state: AppState`.

- [ ] **Step 1: Write `Sources/PopoverView.swift`**

```swift
import SwiftUI

struct PopoverView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Reminders", isOn: $state.remindersEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 13)
                .padding(.top, 11)
                .padding(.bottom, state.statusText == nil && !state.permissionDenied ? 11 : 3)

            if state.permissionDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are turned off for this app.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") { state.openNotificationSettings() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 11)
            } else if let status = state.statusText {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 11)
            }

            Divider()

            Toggle("Sound", isOn: $state.soundEnabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)

            Toggle("Launch at login", isOn: $state.launchAtLogin)
                .padding(.horizontal, 13)
                .padding(.bottom, 7)

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
        }
        .font(.system(size: 13))
        .frame(width: 236)
    }
}
```

- [ ] **Step 2: Replace `Sources/TwentyTwentyTwentyApp.swift`**

Overwrite the Task 1 placeholder with:

```swift
import SwiftUI

@main
struct TwentyTwentyTwentyApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(state: state)
                .task { state.start() }
        } label: {
            Image(state.remindersEnabled ? "MenuBarOn" : "MenuBarOff")
        }
        .menuBarExtraStyle(.window)
    }
}
```

`MenuBarOn` and `MenuBarOff` do not exist yet — they arrive in Task 7. Until
then the build will fail at the asset lookup or show a blank glyph at runtime.
That is expected; do not invent placeholder assets.

- [ ] **Step 3: Verify it compiles**

```bash
xcodegen generate && xcodebuild build -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. Missing image assets are a runtime lookup, not a
compile error, so the build should still succeed.

- [ ] **Step 4: Run tests to confirm nothing regressed**

```bash
xcodebuild test -scheme TwentyTwentyTwenty -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PopoverView.swift Sources/TwentyTwentyTwentyApp.swift
git commit -m "Add menu bar popover with reminders, sound, and login toggles"
```

---

### Task 7: Icons

Generated from code rather than checked in as opaque binaries, so the design
is reviewable and regenerable.

**Files:**
- Create: `Tools/GenerateIcons.swift`
- Create: `Sources/Assets.xcassets/Contents.json`
- Create: `Sources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Sources/Assets.xcassets/MenuBarOn.imageset/Contents.json`
- Create: `Sources/Assets.xcassets/MenuBarOff.imageset/Contents.json`

**Interfaces:**
- Consumes: nothing.
- Produces: image set names `MenuBarOn` and `MenuBarOff` used by Task 6, and `AppIcon`.

Design being implemented (from the spec): the app icon is a dark rounded
square with three "20"s receding toward the top-right — front one solid white,
two behind hollow at decreasing opacity. The menu bar glyph is a solid "20"
with one outlined "20" ghosted behind it; disabled is a single hollow "20".

- [ ] **Step 1: Write `Tools/GenerateIcons.swift`**

```swift
#!/usr/bin/env swift
// Regenerate every icon asset:  swift Tools/GenerateIcons.swift
//
// Drawing the icons in code keeps the design reviewable in the diff and
// regenerable when it changes, rather than being an opaque binary blob.

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Sources/Assets.xcassets")

// MARK: - Drawing helpers

/// One "20" layer: `stroke` > 0 draws it hollow, 0 draws it solid.
func attributes(size: CGFloat, color: NSColor, stroke: CGFloat) -> [NSAttributedString.Key: Any] {
    var attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .bold),
        .kern: -size * 0.04,
    ]
    if stroke > 0 {
        // A positive strokeWidth means stroke-only in AppKit — exactly the
        // hollow look we want for the receding layers.
        attrs[.strokeWidth] = stroke
        attrs[.strokeColor] = color
        attrs[.foregroundColor] = NSColor.clear
    } else {
        attrs[.foregroundColor] = color
    }
    return attrs
}

func drawAppIcon(side: CGFloat, in context: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    // Background: the dark rounded square from option B.
    let inset = side * 0.0
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237)
    let gradient = NSGradient(
        colors: [NSColor(srgbRed: 0.114, green: 0.122, blue: 0.141, alpha: 1),
                 NSColor(srgbRed: 0.063, green: 0.067, blue: 0.078, alpha: 1)]
    )!
    gradient.draw(in: bg, angle: -70)

    // Three "20"s stepping up and to the right.
    let fontSize = side * 0.41
    let step = side * 0.137
    let origin = CGPoint(x: side * 0.137, y: side * 0.18)
    let layers: [(CGFloat, CGFloat)] = [  // (opacity, strokeWidth)
        (0.42, 4.0),
        (0.75, 4.0),
        (1.00, 0.0),
    ]

    for (index, layer) in layers.enumerated() {
        let offset = CGFloat(2 - index) * step
        let point = CGPoint(x: origin.x + offset, y: origin.y + offset)
        let color = NSColor(white: 0.949, alpha: layer.0)
        let string = NSAttributedString(
            string: "20",
            attributes: attributes(size: fontSize, color: color, stroke: layer.1)
        )
        string.draw(at: point)
    }

    NSGraphicsContext.restoreGraphicsState()
}

func drawMenuBarGlyph(enabled: Bool, side: CGFloat, in context: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    // Template images are recoloured by macOS; draw in solid black.
    let ink = NSColor.black

    if enabled {
        NSAttributedString(
            string: "20",
            attributes: attributes(size: side * 0.48, color: ink, stroke: 7.0)
        ).draw(at: CGPoint(x: side * 0.30, y: side * 0.44))

        NSAttributedString(
            string: "20",
            attributes: attributes(size: side * 0.58, color: ink, stroke: 0)
        ).draw(at: CGPoint(x: side * 0.06, y: side * 0.10))
    } else {
        NSAttributedString(
            string: "20",
            attributes: attributes(size: side * 0.58, color: ink, stroke: 7.0)
        ).draw(at: CGPoint(x: side * 0.16, y: side * 0.20))
    }

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Output

func writePNG(side: CGFloat, to url: URL, draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    draw(context.cgContext)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.lastPathComponent)")
}

func writePDF(side: CGFloat, to url: URL, draw: (CGContext) -> Void) {
    var box = CGRect(x: 0, y: 0, width: side, height: side)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    draw(context)
    context.endPDFPage()
    context.closePDF()
    print("wrote \(url.lastPathComponent)")
}

// App icon: the sizes an .appiconset needs.
let iconDir = assets.appending(path: "AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
for side in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(side: CGFloat(side), to: iconDir.appending(path: "icon_\(side).png")) {
        drawAppIcon(side: CGFloat(side), in: $0)
    }
}

// Menu bar glyphs: vector PDFs so they stay crisp at any menu bar scale.
for (name, enabled) in [("MenuBarOn", true), ("MenuBarOff", false)] {
    let dir = assets.appending(path: "\(name).imageset")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    writePDF(side: 18, to: dir.appending(path: "\(name).pdf")) {
        drawMenuBarGlyph(enabled: enabled, side: 18, in: $0)
    }
}
```

- [ ] **Step 2: Write the asset catalog metadata**

`Sources/Assets.xcassets/Contents.json`:

```json
{ "info": { "author": "xcode", "version": 1 } }
```

`Sources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [
    { "idiom": "mac", "scale": "1x", "size": "16x16",     "filename": "icon_16.png" },
    { "idiom": "mac", "scale": "2x", "size": "16x16",     "filename": "icon_32.png" },
    { "idiom": "mac", "scale": "1x", "size": "32x32",     "filename": "icon_32.png" },
    { "idiom": "mac", "scale": "2x", "size": "32x32",     "filename": "icon_64.png" },
    { "idiom": "mac", "scale": "1x", "size": "128x128",   "filename": "icon_128.png" },
    { "idiom": "mac", "scale": "2x", "size": "128x128",   "filename": "icon_256.png" },
    { "idiom": "mac", "scale": "1x", "size": "256x256",   "filename": "icon_256.png" },
    { "idiom": "mac", "scale": "2x", "size": "256x256",   "filename": "icon_512.png" },
    { "idiom": "mac", "scale": "1x", "size": "512x512",   "filename": "icon_512.png" },
    { "idiom": "mac", "scale": "2x", "size": "512x512",   "filename": "icon_1024.png" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

`Sources/Assets.xcassets/MenuBarOn.imageset/Contents.json`:

```json
{
  "images": [
    { "idiom": "universal", "filename": "MenuBarOn.pdf" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": {
    "template-rendering-intent": "template",
    "preserves-vector-representation": true
  }
}
```

`Sources/Assets.xcassets/MenuBarOff.imageset/Contents.json`: identical, with
`MenuBarOff.pdf` as the filename.

- [ ] **Step 3: Generate the images**

```bash
cd /Users/clementsauvage/Github/twenty-twenty-twenty
swift Tools/GenerateIcons.swift
ls Sources/Assets.xcassets/AppIcon.appiconset
```

Expected: seven PNGs and two PDFs written.

- [ ] **Step 4: Build and look at it**

```bash
xcodegen generate && make build && open build
```

Expected: `BUILD SUCCEEDED`. Look at the app icon in Finder at several sizes.

Then run the app and check the menu bar glyph:

```bash
open "build/Twenty twenty twenty.app"
```

The glyph must be legible at 18pt against both a light and a dark menu bar,
and must visibly change between the on and off states. Adjust the font sizes,
offsets, and stroke widths in `Tools/GenerateIcons.swift` and re-run until it
reads well — this is a visual judgement, so iterate rather than accepting the
first output.

- [ ] **Step 5: Commit**

```bash
git add Tools/GenerateIcons.swift Sources/Assets.xcassets
git commit -m "Add code-generated app icon and menu bar glyphs

Drawn from a script so the design stays reviewable in the diff and can
be regenerated when it changes."
```

---

### Task 8: Packaging, cask, and manual verification

**Files:**
- Create: `Casks/twenty-twenty-twenty.rb`
- Create: `README.md`

**Interfaces:**
- Consumes: `make dmg` from Task 1.
- Produces: a distributable `.dmg` and a cask formula.

- [ ] **Step 1: Build the dmg**

```bash
make dmg
```

Expected: `build/TwentyTwentyTwenty.dmg` exists, and a SHA-256 is printed.
Record that hash — the cask needs it.

- [ ] **Step 2: Run the full manual verification**

Install from the dmg (drag to Applications) and work through every case. Do
not skip any; several of these cannot be covered by the unit tests.

1. Launch. The menu bar shows the "off" glyph; no dock icon appears.
2. Open the popover, enable Reminders. The system permission prompt appears.
   Grant it. The glyph switches to the "on" state and the status line reads
   "Next break in 20 min", counting down.
3. Close the lid (or `pmset displaysleepnow`), wait two minutes, reopen.
   The status reads a fresh "Next break in 20 min" and **no** notification
   fired or queued while the screen was off.
4. Lock the screen (⌃⌘Q), wait one minute, unlock. Status shows
   "Paused — screen off" while locked and a fresh 20 minutes on unlock.
5. Let a reminder actually fire. Confirm the banner reads "Look away" with
   the body text, and that it is **gone from Notification Center 10 seconds
   later** — open Notification Center and check.
6. Turn Sound off. Confirm the next reminder is silent but still visible.
7. Turn Launch at login on, restart the Mac, confirm the app comes back.
8. Quit from the popover. Confirm the app fully exits.

To avoid waiting 20 minutes per pass, temporarily lower `Twenty.interval` to
`20` seconds, retest, then **restore it to `20 * 60` and re-run
`xcodebuild test`** before continuing.

- [ ] **Step 3: Write `README.md`**

```markdown
# Twenty twenty twenty

A minimalist macOS menu bar reminder for the 20-20-20 rule: every 20 minutes,
look at something 20 feet away for 20 seconds.

- Lives in the menu bar. No dock icon, no window.
- Reminders pause automatically when the screen sleeps or locks, and start
  over from a full 20 minutes when you come back.
- Notifications delete themselves after 10 seconds, so Notification Center
  never fills up with reminders you have already seen.

## Install

```bash
brew tap clementsauvage/tap
brew install --cask --no-quarantine twenty-twenty-twenty
```

`--no-quarantine` is required for now: the app is not yet notarized, so
without it macOS refuses to open it. It will be dropped once notarization is
in place.

To install without Homebrew, download the `.dmg` from Releases, drag the app
to Applications, then right-click it and choose **Open** the first time.

## Build from source

```bash
brew install xcodegen
make test    # run the test suite
make build   # build the .app into ./build
make dmg     # produce a distributable .dmg
```

## Requirements

macOS 14 Sonoma or later.
```

- [ ] **Step 4: Write `Casks/twenty-twenty-twenty.rb`**

Substitute the real SHA-256 from Step 1 and the real GitHub owner.

```ruby
cask "twenty-twenty-twenty" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA_FROM_MAKE_DMG"

  url "https://github.com/clementsauvage/twenty-twenty-twenty/releases/download/v#{version}/TwentyTwentyTwenty.dmg"
  name "Twenty twenty twenty"
  desc "Menu bar reminder for the 20-20-20 eye rule"
  homepage "https://github.com/clementsauvage/twenty-twenty-twenty"

  depends_on macos: ">= :sonoma"

  app "Twenty twenty twenty.app"

  zap trash: [
    "~/Library/Preferences/com.clementsauvage.TwentyTwentyTwenty.plist",
  ]
end
```

- [ ] **Step 5: Confirm the test suite still passes**

```bash
make test 2>&1 | tail -10
```

Expected: PASS, 15 tests. In particular confirm `Twenty.interval == 1200` —
that it was restored after Step 2.

- [ ] **Step 6: Commit**

```bash
git add README.md Casks
git commit -m "Add Homebrew cask and install documentation

Documents the --no-quarantine requirement, which applies until the app
is notarized."
```

---

## Notes for later

**Notarization.** Once a paid Apple Developer account exists, three changes
retire the `--no-quarantine` caveat: set `CODE_SIGN_IDENTITY` to the
Developer ID Application identity and `DEVELOPMENT_TEAM` to the team ID in
`project.yml`; add `xcrun notarytool submit --wait` and `xcrun stapler staple`
to the `dmg` target in the `Makefile`; drop the `--no-quarantine` flag from
`README.md`. No source changes.

**App Store.** The sandbox is already on with no extra entitlements, no
private APIs are used, and a real `.xcodeproj` is generated, so submission
needs a signing identity and an App Store Connect record rather than any
rework.
