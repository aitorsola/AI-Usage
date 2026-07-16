import SwiftUI

@main
struct AIUsageApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("AI Usage", id: "dashboard") {
            DashboardView(store: store)
        }
        .defaultSize(width: 720, height: 680)

        Window("Conectar con Claude", id: "login") {
            LoginView(store: store, config: .anthropic)
        }
        .windowResizability(.contentSize)

        Window("Conectar con OpenAI", id: "login-openai") {
            LoginView(store: store, config: .openAI)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(store: store)
        }
    }
}
