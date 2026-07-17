//
//  UsageStoreiOS.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import AIUsageCore
import Combine
import WidgetKit

// Network-only counterpart of the macOS UsageStore. iOS has no local CLI logs,
// so this fetches plan limits (Claude, OpenAI) and balance (DeepSeek) straight
// from the provider endpoints and writes the shared widget snapshot.
@MainActor
final class UsageStoreiOS: ObservableObject {
    @Published var anthropic = ProviderData(kind: .anthropic)
    @Published var openAI = ProviderData(kind: .openAI)
    @Published var deepSeek = ProviderData(kind: .deepSeek)
    @Published var isRefreshing = false
    @Published var lastUpdated = Date()

    lazy var anthropicLogin = ProviderLogin(.anthropic) { [weak self] in self?.refresh() }
    lazy var openAILogin = ProviderLogin(.openAI) { [weak self] in self?.refresh() }

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var providers: [ProviderData] { [anthropic, openAI, deepSeek] }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let group = DispatchGroup()
        var claude = PlanStatus(), openAILive = PlanStatus(), ds = PlanStatus()
        group.enter(); PlanFetcher.fetch { claude = $0; group.leave() }
        group.enter(); OpenAIUsageFetcher.fetch { openAILive = $0; group.leave() }
        group.enter(); DeepSeekFetcher.fetch { ds = $0; group.leave() }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.anthropic = ProviderData(kind: .anthropic, plan: claude, available: !claude.needsLogin)
            self.openAI = ProviderData(kind: .openAI, plan: openAILive, available: !openAILive.needsLogin)
            self.deepSeek = ProviderData(kind: .deepSeek, plan: ds, available: !ds.needsLogin)
            self.lastUpdated = Date()
            self.isRefreshing = false
            self.writeSnapshot()
        }
    }

    private var lastReloadFingerprint: WidgetSnapshot?

    func writeSnapshot() {
        let showRemaining = (UserDefaults.standard.string(forKey: SettingsKeys.limitDisplay)
            ?? LimitDisplay.remaining.rawValue) != LimitDisplay.used.rawValue

        var ws: [WSProvider] = []
        for p in providers where p.available {
            let gauges = p.menuGauges.map {
                WSGauge(label: $0.label,
                        used: min(max($0.utilization, 0), 100),
                        reset: $0.resetsAt.map(Formatters.resetCompact))
            }
            var lines: [String] = []
            if p.kind == .deepSeek, let balance = p.plan.credits?.balance {
                lines.append("\(L.t("balance")) \(Formatters.money(balance) ?? balance)")
            }
            ws.append(WSProvider(name: p.kind.name, colorHex: p.kind.colorHex,
                                 subscription: p.plan.subscription, gauges: gauges,
                                 lines: lines, limitReached: p.plan.limitReachedReason))
        }

        let snapshot = WidgetSnapshot(providers: ws, showRemaining: showRemaining,
                                      weekTitle: "", weekBars: [],
                                      updatedText: Formatters.time(lastUpdated), date: lastUpdated)
        WidgetShared.save(snapshot)
        // reloadAllTimelines() is budgeted by WidgetKit; reload only when
        // something the widget shows has changed (see reloadFingerprint).
        let fingerprint = snapshot.reloadFingerprint
        if fingerprint != lastReloadFingerprint {
            lastReloadFingerprint = fingerprint
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
