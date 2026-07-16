//
//  MenuContentView.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI
import AppKit
import ServiceManagement

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKeys.menuSections) private var menuSectionsRaw = MenuSectionsConfig.storageDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !store.hasLoaded {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L.t("reading_usage_data"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                let visible = MenuSectionsConfig.parse(menuSectionsRaw)
                    .filter { $0.visible && isSectionAvailable($0.id) }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, section in
                    if index > 0 { Divider() }
                    sectionView(section.id)
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 330)
    }

    private func isSectionAvailable(_ id: MenuSectionID) -> Bool {
        switch id {
        case .claude, .week: return true
        case .openai: return store.openAI.available || store.openAI.plan.needsLogin
        case .openCode: return store.openCode.available
        case .deepSeek: return store.deepSeek.available
        }
    }

    @ViewBuilder
    private func sectionView(_ id: MenuSectionID) -> some View {
        switch id {
        case .claude: providerSection(store.anthropic, showBlock: true)
        case .openai: providerSection(store.openAI, showBlock: false)
        case .openCode: providerSection(store.openCode, showBlock: false)
        case .deepSeek: providerSection(store.deepSeek, showBlock: false)
        case .week: weekBars
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "asterisk")
                .foregroundStyle(ProviderKind.anthropic.color)
            Text("AI Usage")
                .font(.headline)
            Spacer()
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

    @ViewBuilder
    private func providerSection(_ provider: ProviderData, showBlock: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(provider.kind.color)
                    .frame(width: 8, height: 8)
                Text(provider.kind.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let sub = provider.plan.subscription {
                    Text(sub.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(provider.kind.color.opacity(0.18)))
                }
                Spacer()
                Text(provider.kind.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let reason = provider.plan.limitReachedReason {
                LimitBanner(reason: reason)
            }

            if provider.plan.needsLogin {
                Button {
                    openWindow(id: provider.kind == .anthropic ? "login" : "login-openai")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label(String(format: L.t("sign_in_with"), provider.kind.name),
                          systemImage: "person.crop.circle.badge.plus")
                }
                .tint(provider.kind.color)
                if let error = provider.plan.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if !provider.plan.gauges.isEmpty {
                ForEach(provider.plan.gauges.prefix(3)) { gauge in
                    GaugeRow(gauge: gauge, tint: provider.kind.color)
                }
            } else if let error = provider.plan.error, !provider.plan.hasExtras {
                Text(String(format: L.t("limits"), error))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if provider.plan.hasExtras {
                PlanExtrasView(plan: provider.plan, tint: provider.kind.color)
            }

            if showBlock {
                if let block = provider.snapshot.currentBlock {
                    infoRow(label: L.t("current_block_5_h"),
                            value: Formatters.cost(block.totals.cost),
                            detail: String(format: L.t("ends_at_left"), Formatters.time(block.end), Formatters.remaining(until: block.end)))
                } else {
                    infoRow(label: L.t("current_block_5_h"), value: "—",
                            detail: L.t("no_recent_activity"))
                }
            }

            if provider.kind.hasLocalUsage {
                infoRow(label: L.t("today"),
                        value: Formatters.cost(provider.snapshot.today.cost),
                        detail: "\(provider.snapshot.today.messages) \(L.t("messages_2")) · \(Formatters.tokens(provider.snapshot.today.totalTokens)) tokens")
            }
        }
    }

    private var weekBars: some View {
        VStack(alignment: .leading, spacing: 4) {
            let combined = store.combinedDays
            let title = store.openAI.available ? L.t("last_7_days_total") : L.t("last_7_days")
            let weekCost = combined.suffix(7).reduce(0) { $0 + $1.totals.cost }
            Text("\(title) — \(Formatters.cost(weekCost))")
                .font(.caption)
                .foregroundStyle(.secondary)
            DayBars(days: Array(combined.suffix(7)))
        }
    }

    private func infoRow(label: String, value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .fontWeight(.semibold)
        }
    }

    private var footer: some View {
        HStack {
            Button(L.t("open_app")) {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button {
                ActivationPolicy.windowAppeared()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L.t("settings"))
        }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle(L.t("open_at_login"), isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKeys.limitDisplay) private var limitDisplay = LimitDisplay.remaining.rawValue
    @AppStorage(SettingsKeys.menuSource) private var menuSource = MenuSource.auto.rawValue

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "asterisk")
            Text(titleValues.joined(separator: " · "))
        }
        .onAppear {
            WindowBridge.openWindow = openWindow
            WindowBridge.openSettings = openSettings
            WindowBridge.store = store
            StatusItemRightClickHandler.shared.install()
        }
    }

    private var titleValues: [String] {
        guard store.hasLoaded else { return ["…"] }
        switch MenuSource(rawValue: menuSource) ?? .auto {
        case .anthropic:
            return gaugeValues(store.anthropic)
                ?? [Formatters.cost(store.anthropic.snapshot.today.cost)]
        case .openAI:
            return gaugeValues(store.openAI)
                ?? [Formatters.cost(store.openAI.snapshot.today.cost)]
        case .openCode:
            return ["\(Formatters.tokens(store.openCode.snapshot.today.totalTokens)) tokens"]
        case .deepSeek:
            if let balance = store.deepSeek.plan.credits?.balance {
                return [Formatters.money(balance) ?? balance]
            }
            return ["—"]
        case .cost:
            return [Formatters.cost(store.combinedTodayCost)]
        case .auto:
            return gaugeValues(store.anthropic)
                ?? gaugeValues(store.openAI)
                ?? [Formatters.cost(store.combinedTodayCost)]
        }
    }

    private func gaugeValues(_ provider: ProviderData) -> [String]? {
        let gauges = provider.menuGauges
        guard !gauges.isEmpty else { return nil }
        return gauges.map { gauge in
            let used = min(max(gauge.utilization, 0), 100)
            let shown = limitDisplay == LimitDisplay.used.rawValue ? used : 100 - used
            return "\(Int(shown.rounded()))%"
        }
    }
}
