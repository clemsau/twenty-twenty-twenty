# Twenty twenty twenty

A minimalist macOS menu bar reminder for the 20-20-20 rule: every 20 minutes,
look at something 20 feet away for 20 seconds.

- Lives in the menu bar. No dock icon, no window.
- Reminders pause automatically when the screen sleeps or locks, and start
  over from a full 20 minutes when you come back.
- Notifications delete themselves after 10 seconds, so Notification Center
  never fills up with reminders you have already seen.

## Install

> **Not released yet.** The commands below point at a GitHub release that does
> not exist at the time of writing. Until `v1.0.0` is published they will fail
> with a download error. Build from source in the meantime — see below.

```bash
brew tap clementsauvage/twenty-twenty-twenty https://github.com/clementsauvage/twenty-twenty-twenty
brew install --cask --no-quarantine clementsauvage/twenty-twenty-twenty/twenty-twenty-twenty
```

The first command points Homebrew at this repository, which holds the cask in
`Casks/`. It is not a conventional `clementsauvage/tap` tap, so the repository
URL has to be given explicitly and the cask has to be installed by its full
name.

`--no-quarantine` is required. It is not optional and not a preference. The
app is signed ad-hoc rather than with an Apple Developer ID, and it is not
notarized, so Gatekeeper will refuse to open it if Homebrew attaches its usual
quarantine flag. Without this flag the install appears to succeed and the app
then fails to launch. The flag will be dropped once the app is notarized.

### Without Homebrew

1. Download `TwentyTwentyTwenty.dmg` from the Releases page.
2. Open it and drag **Twenty twenty twenty** to your Applications folder.
3. The first launch needs one extra step, for the same
   not-notarized-yet reason as above:
   - **macOS 14 Sonoma:** right-click the app in Applications and choose
     **Open**, then **Open** again in the dialog.
   - **macOS 15 Sequoia and later:** double-click it, let macOS block it, then
     go to **System Settings > Privacy & Security**, scroll down, and click
     **Open Anyway**.

   Or, from Terminal:
   `xattr -dr com.apple.quarantine "/Applications/Twenty twenty twenty.app"`

You only have to do this once.

## Using it

The app has no dock icon and no window — it is only the small "20" in your
menu bar at the top right of the screen. Click it to open the popover.

Turn **Reminders** on. macOS will ask permission to send you notifications;
you have to allow this or there is nothing for the app to show you. The
popover then counts down to your next break. **Sound**, **Launch at login**,
and **Quit** are in the same popover.

## Build from source

Until `v1.0.0` is published this is the only way to install the app, and it
works today.

You need **Xcode** from the Mac App Store — the Command Line Tools alone are
not enough, because the build uses the macOS SDK and the Swift Testing
framework that ship inside Xcode. Open Xcode once after installing it so it can
finish its first-run setup. Then:

```bash
git clone https://github.com/clementsauvage/twenty-twenty-twenty.git
cd twenty-twenty-twenty
brew install xcodegen
make build   # build the .app into ./build
```

`make build` puts the app at `build/Twenty twenty twenty.app`. Drag it into
your **Applications** folder — in Finder, or from Terminal:

```bash
cp -R "build/Twenty twenty twenty.app" /Applications/
```

An app you built yourself is not quarantined, so it opens on the first
double-click with no Gatekeeper prompt. There is no dock icon and no window —
look for the small "20" in the menu bar.

Two other targets, neither needed just to install:

```bash
make test    # run the test suite
make dmg     # produce a distributable .dmg (for cutting a release)
```

## Releasing (maintainer notes)

`make dmg` prints the SHA-256 of the `.dmg` it just built. **That hash is only
valid for that exact file.** macOS builds are not bit-for-bit reproducible, so
rebuilding produces a different hash. When cutting a release, upload the very
same `build/TwentyTwentyTwenty.dmg` whose hash you put in
`Casks/twenty-twenty-twenty.rb` — if you rebuild after updating the cask,
`brew install` will fail its checksum check.

`Casks/twenty-twenty-twenty.rb` is the canonical copy of the cask. If a
dedicated `homebrew-tap` repository is created later, copy the file there;
users can then use the shorter `brew tap clementsauvage/tap` form and the
install instructions above should be updated to match.

The GitHub owner in the cask's `url` and `homepage` is assumed to be
`clementsauvage`, matching the bundle identifier. Confirm it before the first
release.

## Requirements

macOS 14 Sonoma or later.
