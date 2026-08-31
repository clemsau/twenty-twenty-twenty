# Twenty twenty twenty — Design

**Date:** 2026-08-31
**Status:** Approved

## Purpose

A minimalist macOS menu bar app that reminds the user to follow the 20-20-20
rule: every 20 minutes, look at something 20 feet away for 20 seconds.

The app has no dock icon and no main window. It posts a notification every 20
minutes while the user is actually at the screen, and leaves no trace in
Notification Center afterwards.

## Non-goals

- No tracking, statistics, streaks, or history.
- No configurable interval. The rule is 20-20-20; a settings screen for it
  would be more UI than the app deserves.
- No signal that the 20-second break is over. One ping per cycle; the user
  estimates the 20 seconds.
- No suppression for fullscreen video, presentations, or Do Not Disturb.

## Platform

- macOS 14 Sonoma minimum (`SMAppService` and `@Observable` both require it).
- Single Xcode app target, SwiftUI, `MenuBarExtra`.
- App Sandbox enabled from day one. The app needs no entitlements beyond the
  default, so this costs nothing now and avoids rework at App Store submission.

## Architecture

Four units. Only the first contains logic worth testing; the rest are thin.

### `ReminderScheduler`

Pure logic. No AppKit import. Owns the state machine. Takes an injected clock
and a `Notifier` protocol so tests drive it without real time or real
notifications.

Three states:

- **disabled** — the toggle is off.
- **counting** — screen is active; an absolute deadline is set.
- **suspended** — screen is off or locked; no deadline.

Transitions:

| Event | Effect |
|---|---|
| Toggle on, screen active | → counting, deadline = now + 20 min |
| Toggle on, screen inactive | → suspended |
| Deadline reached | fire notification; deadline = now + 20 min; stay counting |
| Screen sleeps or locks | → suspended, clear deadline |
| Screen wakes or unlocks | → counting, deadline = now + 20 min (fresh) |
| Toggle off | → disabled, clear deadline |

**Timing.** The deadline is an absolute `Date`. A 1-second `Timer` compares it
against `Date.now`. Elapsed time is never accumulated, so a missed tick or a
system clock jump self-corrects on the following tick rather than drifting.

A 1-second poll rather than a single 20-minute timer, because the countdown
label needs the tick anyway, lock-state polling rides along for free, and a
long timer is what App Nap coalesces most aggressively.

**App Nap.** While in `counting`, hold an activity token from
`ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)`. This
exempts the app from App Nap — which otherwise delays timers by minutes —
while still allowing the Mac to sleep normally. The token is released on
entering `suspended` or `disabled`.

### `ScreenStateMonitor`

Publishes `.active` / `.inactive`. Combines `NSWorkspace` sleep and wake
notifications with a `CGSessionCopyCurrentDictionary()` check for lock and
screensaver state, evaluated on the scheduler's existing 1-second tick.

`CGSessionCopyCurrentDictionary` is used in preference to the
`com.apple.screenIsLocked` distributed notification: it is public API, works
under the sandbox, and carries no App Store review risk.

Knows nothing about timers or notifications.

### `SystemNotifier`

Conforms to `Notifier`. Wraps `UNUserNotificationCenter`:

- Requests authorization on first enable, not at launch, so the system prompt
  appears with obvious context.
- Posts a notification with a title and a body
  (e.g. "Look away" / "Focus on something 20 feet away for 20 seconds").
- Plays the default sound when `soundEnabled` is set.
- Removes the delivered notification from Notification Center 10 seconds after
  posting. This is the requirement that it leave no trace: a past reminder has
  no value to review.

### `AppState`

The `@Observable` the popover binds to:

- `remindersEnabled` — persisted to `UserDefaults`
- `soundEnabled` — persisted to `UserDefaults`
- `launchAtLogin` — persisted, mirrored to `SMAppService.mainApp`
- `secondsUntilNextBreak` — derived, not persisted

## Interface

`MenuBarExtra` with `.menuBarExtraStyle(.window)`. `LSUIElement = true` in
Info.plist: no dock icon, no main window. The popover is the entire app.

**Popover**, fixed 236pt wide, height following content:

1. "Reminders" label with a switch
2. Status line, dimmed, small: "Next break in 12 min" while counting;
   "Paused — screen off" while suspended; hidden while disabled
3. Divider
4. "Sound" checkbox
5. "Launch at login" checkbox
6. Divider
7. "Quit" (⌘Q) — required, since with no dock icon there is no other way out

**Error path.** If notification authorization is denied, the popover replaces
the status line with a single line of explanation and a button opening System
Settings, and the reminders toggle stays off. This is the only error state in
the app.

### Icon

App icon: a dark rounded square; three "20"s receding toward the top-right
with a slight upward offset. The front one is solid white; the two behind are
hollow outlines at decreasing opacity. Outlines rather than a fade, because
they stay legible at small sizes.

Menu bar glyph: a template PDF. Enabled is a solid "20" with a single
outlined "20" ghosted behind it; disabled is one hollow "20". Template mode
lets macOS handle light and dark menu bars and tinting.

## Packaging and distribution

Xcode builds the `.app`. A `Makefile` wraps `xcodebuild archive` and export
into a `.dmg`.

Distribution is a Homebrew cask in the author's own tap, with
`depends_on macos: ">= :sonoma"`. The App Store is a later goal; the design
choices above (sandbox, no private API, `.xcodeproj`) keep that path open.

**Signing.** Ad-hoc initially — required for the app to launch at all on Apple
Silicon. Homebrew quarantines cask apps, so until notarization is in place the
README must document installing with `--no-quarantine`. Moving to a Developer
ID identity is a build-setting change, not a code change.

## Testing

Swift Testing against `ReminderScheduler`, with a fake clock and a spy
notifier. No test waits on real time.

Cases:

- Fires at 20 minutes and reschedules for another 20.
- Screen sleeping mid-count cancels the pending notification.
- Waking restarts from a full 20 minutes rather than firing immediately.
- Disabling mid-count clears the deadline.
- A forward system clock jump fires once, not repeatedly.

`ScreenStateMonitor` and `SystemNotifier` are thin wrappers over Apple APIs.
They are verified by hand rather than mocked.

**Manual verification before shipping:**

1. Enable reminders; confirm the countdown ticks down.
2. Close the lid, wait, reopen. The countdown reads a fresh 20:00 and no
   notifications queued up while the lid was shut.
3. Let a reminder fire. Confirm it is gone from Notification Center 10 seconds
   later.
4. Toggle sound off; confirm the next reminder is silent.
5. Toggle launch at login; confirm the app reappears after a restart.
