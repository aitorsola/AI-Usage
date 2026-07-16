//
//  AIUsageiOSApp.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI

@main
struct AIUsageiOSApp: App {
    @StateObject private var store = UsageStoreiOS()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
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
                    ProviderCard(data: provider)
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
            }
        }
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
            ProgressView(value: used, total: 100).tint(tint)
            if let resets = gauge.resetsAt {
                Text(Formatters.resetCompact(resets))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var store: UsageStoreiOS
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

                Section("Claude") {
                    if AnthropicTokenStore.load() == nil {
                        Button(L.t("sign_in_with_claude")) { store.anthropicLogin.begin() }
                            .tint(ProviderKind.anthropic.brand)
                    } else {
                        Button(L.t("sign_out"), role: .destructive) {
                            AnthropicTokenStore.delete(); store.refresh()
                        }
                    }
                }

                Section("OpenAI") {
                    if OpenAITokenStore.load() == nil {
                        Button(L.t("sign_in_with_openai")) { store.openAILogin.begin() }
                            .tint(ProviderKind.openAI.brand)
                    } else {
                        Button(L.t("sign_out"), role: .destructive) {
                            OpenAITokenStore.delete(); store.refresh()
                        }
                    }
                }

                Section("DeepSeek") {
                    if DeepSeekKeyStore.load() == nil {
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
            }
            .navigationTitle("AI Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
        }
    }
}
