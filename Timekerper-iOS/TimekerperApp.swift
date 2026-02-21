import SwiftUI

@main
struct TimekerperApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.settings.darkMode ? .dark : .light)
        }
    }
}
