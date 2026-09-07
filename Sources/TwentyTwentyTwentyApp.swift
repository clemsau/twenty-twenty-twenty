import SwiftUI

@main
struct TwentyTwentyTwentyApp: App {
    @State private var state: AppState

    init() {
        // start() is called here, at launch, and NOT from the popover's .task.
        // A MenuBarExtra's content view is built lazily on first open and torn
        // down on close, so a .task there would neither run at launch — leaving
        // a user who had reminders on with no reminders, and the menu bar glyph
        // stuck on the "off" image until something opened the popover — nor run
        // only once. App.init runs exactly once, before any scene is built.
        let state = AppState()
        state.start()
        _state = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(state: state)
        } label: {
            Image(state.remindersEnabled ? "MenuBarOn" : "MenuBarOff")
        }
        .menuBarExtraStyle(.window)
    }
}
