import SwiftUI

@main
struct InkPulseApp: App {
    @StateObject private var appState: AppState = {
        let state = AppState()
        state.start()
        return state
    }()

    var body: some Scene {
        Window("InkPulse", id: "dashboard") {
            TabbedDashboard(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 680, height: 640)

        MenuBarExtra(appState.menuBarLabel) {
            PopoverView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
