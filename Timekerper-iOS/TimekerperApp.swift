import SwiftUI

@main
struct TimekerperApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(
                    appState.settings.darkMode == "on" ? .dark :
                    appState.settings.darkMode == "off" ? .light : nil
                )
        }
    }
}
