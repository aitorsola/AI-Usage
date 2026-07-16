//
//  DashboardView.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI
import AIUsageCore
import AppKit

struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var selectedProvider = ProviderKind.anthropic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                providerPicker
                providerPage(current)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 660, idealWidth: 720, minHeight: 560, idealHeight: 680)
        .onAppear { ActivationPolicy.windowAppeared() }
        .onDisappear { ActivationPolicy.windowClosed() }
    }

    private var current: ProviderData {
        switch selectedProvider {
        case .anthropic: return store.anthropic
        case .openAI: return store.openAI
        case .openCode: return store.openCode
        case .deepSeek: return store.deepSeek
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "asterisk")
                .font(.title2)
                .foregroundStyle(current.kind.color)
            Text("AI Usage")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Text(String(format: L.t("updated_at"), Formatters.time(store.lastUpdated)))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L.t("refresh_now"))
            }
        }
    }

    private var providerPicker: some View {
        HStack {
            Picker("", selection: $selectedProvider) {
                ForEach(ProviderKind.allCases, id: \.self) { kind in
                    Text(kind.name).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .tint(current.kind.color)
            if let sub = current.plan.subscription {
                Text(String(format: L.t("plan_badge"), sub.capitalized))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(current.kind.color.opacity(0.18)))
            }
            Text(current.kind.detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    @ViewBuilder
    private func providerPage(_ provider: ProviderData) -> some View {
        if provider.kind == .deepSeek {
            deepSeekPage(provider)
        } else if provider.kind == .openAI && !provider.available && !provider.plan.needsLogin {
            section("OpenAI") {
                Text(provider.plan.error ?? L.t("no_codex_cli_sessions_found_in"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if provider.kind == .openCode && !provider.available {
            section("OpenCode") {
                Text(L.t("no_opencode_data"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            statTiles(provider)
            planSection(provider)
            dailySection(provider)
            modelSection(provider)
        }
    }

    @ViewBuilder
    private func deepSeekPage(_ provider: ProviderData) -> some View {
        if provider.plan.needsLogin {
            section(L.t("balance")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(provider.plan.error ?? L.t("add_deepseek_key_in_settings"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(L.t("open_settings")) {
                        ActivationPolicy.windowAppeared()
                        openSettings()
                    }
                    .tint(provider.kind.color)
                }
            }
        } else {
            section(L.t("balance")) {
                VStack(alignment: .leading, spacing: 14) {
                    if let reason = provider.plan.limitReachedReason {
                        LimitBanner(reason: reason)
                    }
                    if provider.plan.hasExtras {
                        PlanExtrasView(plan: provider.plan, tint: provider.kind.color)
                            .frame(maxWidth: 360)
                    }
                    if let error = provider.plan.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func loginButton(_ provider: ProviderData) -> some View {
        Button {
            openWindow(id: provider.kind == .anthropic ? "login" : "login-openai")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label(String(format: L.t("sign_in_with"), provider.kind.name),
                  systemImage: "person.crop.circle.badge.plus")
        }
        .tint(provider.kind.color)
    }

    private func statTiles(_ provider: ProviderData) -> some View {
        let snap = provider.snapshot
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatTile(title: L.t("today"),
                     value: Formatters.cost(snap.today.cost),
                     detail: "\(snap.today.messages) \(L.t("messages_2")) · \(Formatters.tokens(snap.today.totalTokens)) tokens")
            if let block = snap.currentBlock {
                StatTile(title: L.t("current_block_5_h"),
                         value: Formatters.cost(block.totals.cost),
                         detail: String(format: L.t("ends_at"), Formatters.time(block.end)))
            } else {
                StatTile(title: L.t("current_block_5_h"),
                         value: "—",
                         detail: L.t("no_recent_activity"))
            }
            StatTile(title: L.t("last_7_days"),
                     value: Formatters.cost(snap.last7.cost),
                     detail: "\(Formatters.tokens(snap.last7.totalTokens)) tokens")
            StatTile(title: L.t("last_30_days"),
                     value: Formatters.cost(snap.last30.cost),
                     detail: "\(Formatters.tokens(snap.last30.totalTokens)) tokens")
        }
    }

    @ViewBuilder
    private func planSection(_ provider: ProviderData) -> some View {
        if provider.plan.needsLogin {
            section(L.t("plan_limits")) {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = provider.plan.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    loginButton(provider)
                }
            }
        } else if !provider.plan.gauges.isEmpty || provider.plan.hasExtras {
            section(L.t("plan_limits")) {
                VStack(alignment: .leading, spacing: 14) {
                    if let reason = provider.plan.limitReachedReason {
                        LimitBanner(reason: reason)
                    }
                    if !provider.plan.gauges.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 2),
                                  alignment: .leading, spacing: 14) {
                            ForEach(provider.plan.gauges) { gauge in
                                GaugeRow(gauge: gauge, tint: provider.kind.color)
                            }
                        }
                    }
                    if provider.plan.hasExtras {
                        PlanExtrasView(plan: provider.plan, tint: provider.kind.color)
                            .frame(maxWidth: 360)
                    }
                }
            }
        } else if let error = provider.plan.error {
            section(L.t("plan_limits")) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dailySection(_ provider: ProviderData) -> some View {
        let days = Array(provider.snapshot.days.suffix(14)).reversed()
        let maxCost = provider.snapshot.days.suffix(14).map(\.totals.cost).max() ?? 0
        return section(L.t("last_14_days")) {
            VStack(spacing: 6) {
                ForEach(Array(days)) { day in
                    DailyRow(day: day, maxCost: maxCost, tint: provider.kind.color)
                }
            }
        }
    }

    @ViewBuilder
    private func modelSection(_ provider: ProviderData) -> some View {
        if !provider.snapshot.models.isEmpty {
            section(L.t("by_model_last_30_days")) {
                VStack(spacing: 4) {
                    modelHeaderRow
                    ForEach(provider.snapshot.models) { model in
                        modelRow(model)
                    }
                }
            }
        }
    }

    private var modelHeaderRow: some View {
        HStack {
            Text(L.t("model")).frame(width: 130, alignment: .leading)
            Spacer()
            Text(L.t("messages")).frame(width: 70, alignment: .trailing)
            Text(L.t("input")).frame(width: 70, alignment: .trailing)
            Text(L.t("output")).frame(width: 70, alignment: .trailing)
            Text(L.t("cache")).frame(width: 70, alignment: .trailing)
            Text(L.t("cost")).frame(width: 70, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func modelRow(_ model: ModelUsage) -> some View {
        HStack {
            Text(Formatters.modelName(model.model))
                .font(.caption)
                .frame(width: 130, alignment: .leading)
                .help(model.model)
            Spacer()
            Group {
                Text("\(model.totals.messages)").frame(width: 70, alignment: .trailing)
                Text(Formatters.tokens(model.totals.input)).frame(width: 70, alignment: .trailing)
                Text(Formatters.tokens(model.totals.output)).frame(width: 70, alignment: .trailing)
                Text(Formatters.tokens(model.totals.cacheRead + model.totals.cacheWrite))
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            Text(Formatters.cost(model.totals.cost))
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
