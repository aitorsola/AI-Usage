//
//  AIUsageiOSApp.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI
import AIUsageCore

// WatchConnectivity launches the app in the background to deliver what the
// watch sends (handover acknowledgements, session status). The session must be
// active by then — a view's state object is not guaranteed to exist in such a
// launch, so activation happens here.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WatchSync.shared.activate()
        return true
    }
}

@main
struct AIUsageiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStoreiOS()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                // The refresh timer dies while the app is suspended; fetch as
                // soon as we are foregrounded so the widget snapshot catches up.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refresh() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: UsageStoreiOS
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.providers, id: \.kind) { provider in
                    ProviderCard(data: provider, health: store.health[provider.kind])
                }
            }
            .navigationTitle("AI Usage")
            .refreshable { store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.isRefreshing {
                        ProgressView()
                    } else {
                        Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet().environmentObject(store)
            }
        }
    }
}

private struct ProviderCard: View {
    let data: ProviderData
    var health: PlatformHealth? = nil

    var body: some View {
        Section {
            if data.plan.needsLogin || !data.available {
                Text(data.plan.error ?? L.t("not_signed_in"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if let reason = data.plan.limitReachedReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ForEach(data.plan.gauges) { gauge in
                    GaugeBar(gauge: gauge, tint: data.kind.brand)
                }
                if let balance = data.plan.credits?.balance {
                    LabeledContent(L.t("balance"), value: Formatters.money(balance) ?? balance)
                }
            }
        } header: {
            HStack(spacing: 7) {
                Circle().fill(data.kind.brand).frame(width: 9, height: 9)
                Text(data.kind.name)
                if let sub = data.plan.subscription {
                    Text(sub.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let health {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: health.iconName)
                        Text(health.label)
                    }
                    .font(.caption2)
                    .foregroundStyle(Color(hex: health.colorHex))
                }
            }
        }
    }
}

// Drawn by hand rather than with ProgressView so the tint is deterministic and
// the bar matches the widgets and the watch app — see CapsuleBar on macOS.
private struct CapsuleBar: View {
    let value: Double          // 0…100
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        let fraction = min(max(value, 0), 100) / 100
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule().fill(tint)
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}

private struct GaugeBar: View {
    let gauge: PlanGauge
    var tint: Color
    @AppStorage(SettingsKeys.limitDisplay) private var limitDisplay = LimitDisplay.remaining.rawValue

    var body: some View {
        let used = min(max(gauge.utilization, 0), 100)
        let showRemaining = limitDisplay != LimitDisplay.used.rawValue
        let shown = showRemaining ? 100 - used : used
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(gauge.label).font(.subheadline)
                Spacer()
                Text("\(Int(shown.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            CapsuleBar(value: shown, tint: color(used: used))
            if let resets = gauge.resetsAt {
                Text(Formatters.resetCompact(resets))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func color(used: Double) -> Color {
        switch used {
        case 90...: return .red
        case 70..<90: return .orange
        default: return tint
        }
    }
}

// An OAuth provider section that surfaces sign-in progress AND failures —
// previously a failed exchange or a closed browser sheet left no feedback.
private struct OAuthSection: View {
    let title: String
    let signInLabel: String
    let brand: Color
    let signedIn: Bool
    @ObservedObject var login: ProviderLogin
    let onSignOut: () -> Void

    var body: some View {
        Section(title) {
            if signedIn {
                Button(L.t("sign_out"), role: .destructive) { onSignOut() }
            } else {
                Button(signInLabel) { login.begin() }.tint(brand)
                switch login.phase {
                case .waiting:
                    label(L.t("waiting_for_browser_authorization"), "safari", .secondary)
                case .exchanging:
                    label(L.t("exchanging_the_code_for_a_session"), "arrow.triangle.2.circlepath", .secondary)
                case .failed(let message):
                    label(message, "exclamationmark.triangle.fill", .orange)
                case .idle:
                    EmptyView()
                }
            }
        }
    }

    private func label(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var store: UsageStoreiOS
    @ObservedObject private var watchSync = WatchSync.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.limitDisplay) private var limitDisplay = LimitDisplay.remaining.rawValue
    @State private var deepSeekKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L.t("display")) {
                    Picker(L.t("show_limits_as"), selection: $limitDisplay) {
                        ForEach(LimitDisplay.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                // Signed-in state follows whether the session actually WORKS
                // (plan.needsLogin), not merely whether a stale token sits in
                // the keychain — otherwise a dead session still reads as
                // "signed in" here while the dashboard says it expired.
                OAuthSection(title: "Claude",
                             signInLabel: L.t("sign_in_with_claude"),
                             brand: ProviderKind.anthropic.brand,
                             signedIn: !(store.anthropic.plan.needsLogin || AnthropicTokenStore.load() == nil),
                             login: store.anthropicLogin,
                             onSignOut: { AnthropicTokenStore.delete(); store.refresh() })

                OAuthSection(title: "OpenAI",
                             signInLabel: L.t("sign_in_with_openai"),
                             brand: ProviderKind.openAI.brand,
                             signedIn: !(store.openAI.plan.needsLogin || OpenAITokenStore.load() == nil),
                             login: store.openAILogin,
                             onSignOut: { OpenAITokenStore.delete(); store.refresh() })

                Section("DeepSeek") {
                    if store.deepSeek.plan.needsLogin || DeepSeekKeyStore.load() == nil {
                        SecureField(L.t("paste_api_key"), text: $deepSeekKey)
                        Button(L.t("save")) {
                            DeepSeekKeyStore.save(deepSeekKey); deepSeekKey = ""; store.refresh()
                        }
                        .tint(ProviderKind.deepSeek.brand)
                        .disabled(deepSeekKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button(L.t("sign_out"), role: .destructive) {
                            DeepSeekKeyStore.delete(); store.refresh()
                        }
                    }
                }

                if watchSync.isWatchAvailable {
                    Section {
                        WatchRow(kind: .anthropic, state: watchSync.link[.anthropic] ?? .none,
                                 login: store.anthropicWatchLogin)
                        WatchRow(kind: .openAI, state: watchSync.link[.openAI] ?? .none,
                                 login: store.openAIWatchLogin)
                        if DeepSeekKeyStore.load() != nil {
                            WatchRow(kind: .deepSeek, state: watchSync.link[.deepSeek] ?? .none, login: nil)
                        }
                    } header: {
                        Text(L.t("apple_watch"))
                    } footer: {
                        Text(L.t("watch_explanation"))
                    }
                }
            }
            .navigationTitle("AI Usage")
            .navigationBarTitleDisplayMode(.inline)
            // The display mode is baked into the widget snapshot; push it to
            // the widget right away instead of waiting for the next refresh.
            .onChange(of: limitDisplay) { store.writeSnapshot() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
        }
    }
}

// One provider's session on the watch: its state as the watch last reported
// it, and the action that follows — connect (a second authorization, handed
// over), or disconnect. DeepSeek has no login: the phone's key is sent as is.
private struct WatchRow: View {
    let kind: ProviderKind
    let state: WatchLinkState
    let login: ProviderLogin?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(kind.brand).frame(width: 9, height: 9)
                Text(kind.name)
                Spacer()
                Text(stateLabel)
                    .font(.caption)
                    .foregroundStyle(stateColor)
                    .multilineTextAlignment(.trailing)
            }
            switch state {
            case .connected, .pending:
                Button(L.t("disconnect_from_watch"), role: .destructive) {
                    WatchSync.shared.disconnect(kind)
                }
                .font(.callout)
            case .none, .expired:
                if let login {
                    Button(String(format: L.t("connect_on_watch"), kind.name)) { login.begin() }
                        .font(.callout)
                        .tint(kind.brand)
                    LoginProgress(login: login)
                } else {
                    Button(L.t("send_key_to_watch")) { WatchSync.shared.handOver(kind) }
                        .font(.callout)
                        .tint(kind.brand)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var stateLabel: String {
        switch state {
        case .none: return L.t("watch_not_connected")
        case .pending: return L.t("watch_pending_delivery")
        case .connected: return L.t("watch_connected")
        case .expired: return L.t("watch_session_expired")
        }
    }

    private var stateColor: Color {
        switch state {
        case .connected: return .secondary
        case .pending: return .orange
        case .expired: return .red
        case .none: return .secondary
        }
    }
}

private struct LoginProgress: View {
    @ObservedObject var login: ProviderLogin

    var body: some View {
        switch login.phase {
        case .waiting:
            Label(L.t("waiting_for_browser_authorization"), systemImage: "safari")
                .font(.caption).foregroundStyle(.secondary)
        case .exchanging:
            Label(L.t("exchanging_the_code_for_a_session"), systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }
}
