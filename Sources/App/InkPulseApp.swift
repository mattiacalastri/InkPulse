import SwiftUI

@main
struct InkPulseApp: App {
    @StateObject private var appState: AppState = {
        let state = AppState()
        state.start()
        return state
    }()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(appState: appState)
        } label: {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
