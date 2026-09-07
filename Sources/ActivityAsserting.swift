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
