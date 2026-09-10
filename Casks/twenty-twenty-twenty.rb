# This cask lives in the app's own repository, which is tapped directly:
#
#   brew tap clementsauvage/twenty-twenty-twenty https://github.com/clementsauvage/twenty-twenty-twenty
#   brew install --cask --no-quarantine clementsauvage/twenty-twenty-twenty/twenty-twenty-twenty
#
# --no-quarantine is required until the app is notarized; it is ad-hoc signed,
# so Gatekeeper refuses to open it if Homebrew attaches the quarantine flag.
#
# The sha256 below is of a specific locally built dmg. macOS builds are not
# bit-for-bit reproducible, so it is ONLY valid if that exact file is the one
# attached to the release. Rebuilding after editing this file will break the
# checksum. Re-run `make dmg`, take the printed hash, and upload that same dmg.
cask "twenty-twenty-twenty" do
  version "1.0.0"
  sha256 "3bd73775235d0fe3e1b1b66a97ee00c41f8dab4d667f618a4663d1e6d9390c2c"

  url "https://github.com/clementsauvage/twenty-twenty-twenty/releases/download/v#{version}/TwentyTwentyTwenty.dmg"
  name "Twenty twenty twenty"
  desc "Menu bar reminder for the 20-20-20 eye rule"
  homepage "https://github.com/clementsauvage/twenty-twenty-twenty"

  depends_on macos: :sonoma

  app "Twenty twenty twenty.app"

  # The app is sandboxed, so macOS redirects its UserDefaults into the container
  # rather than ~/Library/Preferences. Removing the container removes the
  # preferences with it.
  zap trash: [
    "~/Library/Application Scripts/com.clementsauvage.TwentyTwentyTwenty",
    "~/Library/Containers/com.clementsauvage.TwentyTwentyTwenty",
  ]
end
