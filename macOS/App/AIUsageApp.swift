//
//  AIUsageApp.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI
import AIUsageCore
import AppKit

@main
struct AIUsageApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
                .modifier(WidgetURLHandler())
        }
        .menuBarExtraStyle(.window)

        Window("AI Usage", id: "dashboard") {
            DashboardView(store: store)
        }
        .defaultSize(width: 720, height: 680)
        // Widget clicks arrive as aiusage://dashboard: route them to this window.
        .handlesExternalEvents(matching: ["dashboard"])

        Window(String(format: L.t("connect_with"), "Claude"), id: "login") {
            LoginView(store: store, config: .anthropic)
        }
        .windowResizability(.contentSize)

        Window(String(format: L.t("connect_with"), "OpenAI"), id: "login-openai") {
            LoginView(store: store, config: .openAI)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(store: store)
        }
    }
}

// Opens the dashboard when a widget is clicked (aiusage:// deep link). Attached
// to the menu bar label because it is the only view that is always installed.
private struct WidgetURLHandler: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.scheme == "aiusage" else { return }
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
