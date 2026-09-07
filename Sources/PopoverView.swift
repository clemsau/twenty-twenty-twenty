import AppKit
import SwiftUI

/// The entire UI of the app: one panel hanging off the menu bar item.
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

            // Required: with LSUIElement there is no dock icon and no menu bar
            // application menu, so this is the only way to quit.
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
