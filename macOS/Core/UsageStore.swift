//
//  UsageStore.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import AIUsageCore
import Combine
import WidgetKit

final class UsageStore: ObservableObject {
    @Published var anthropic = ProviderData(kind: .anthropic)
    @Published var openAI = ProviderData(kind: .openAI)
    @Published var openCode = ProviderData(kind: .openCode)
    @Published var deepSeek = ProviderData(kind: .deepSeek)
    @Published var isRefreshing = false
    @Published var hasLoaded = false
    @Published var lastUpdated = Date()

    private let claudeParser = UsageParser()
    private let codexParser = CodexParser()
    private let openCodeParser = OpenCodeParser()
    private let queue = DispatchQueue(label: "aiusage.refresh", qos: .utility)
    private var timer: Timer?
    private var refreshing = false

    init() {
//        if UserDefaults.standard.bool(forKey: "demo") {
//            loadDemo()
//            return
//        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // Populate with fabricated, privacy-safe data for screenshots (see DemoData).
    private func loadDemo() {
        let d = DemoData.make()
        anthropic = d.anthropic
        openAI = d.openAI
        openCode = d.openCode
        deepSeek = d.deepSeek
        lastUpdated = Date()
        hasLoaded = true
        updateWidgetSnapshot()
    }

    func refresh() {
        DispatchQueue.main.async {
            guard !self.refreshing else { return }
            self.refreshing = true
            self.isRefreshing = true
            self.queue.async {
                let cutoff = Calendar.current.date(byAdding: .day, value: -35, to: Date())!

                let claudeEvents = self.claudeParser.collectEvents(since: cutoff)
                let claudeSnap = Aggregator.snapshot(from: claudeEvents)

                let codex = self.codexParser.collect(since: cutoff)
                let codexSnap = Aggregator.snapshot(from: codex.events)

                let opencode = self.openCodeParser.collect(since: cutoff)
                let opencodeSnap = Aggregator.snapshot(from: opencode.events)

                let group = DispatchGroup()
                var claudePlan = PlanStatus()
                var openAILive = PlanStatus()
                var deepSeekPlan = PlanStatus()
                group.enter()
                PlanFetcher.fetch { claudePlan = $0; group.leave() }
                group.enter()
                OpenAIUsageFetcher.fetch { openAILive = $0; group.leave() }
                group.enter()
                DeepSeekFetcher.fetch { deepSeekPlan = $0; group.leave() }

                group.notify(queue: .main) {
                    var openAIPlan = openAILive
                    if openAIPlan.gauges.isEmpty && openAIPlan.error == nil {
                        openAIPlan.error = L.t("no_limit_data")
                    }
                    let openAIAvailable = codex.installed
                        || !openAIPlan.gauges.isEmpty
                        || codexSnap.last30.messages > 0

                    self.anthropic = ProviderData(kind: .anthropic, snapshot: claudeSnap,
                                                  plan: claudePlan, available: true)
                    self.openAI = ProviderData(kind: .openAI, snapshot: codexSnap,
                                               plan: openAIPlan, available: openAIAvailable)
                    self.openCode = ProviderData(kind: .openCode, snapshot: opencodeSnap,
                                                 plan: PlanStatus(),
                                                 available: opencode.installed && opencodeSnap.last30.messages > 0)
                    self.deepSeek = ProviderData(kind: .deepSeek, snapshot: UsageSnapshot(),
                                                 plan: deepSeekPlan,
                                                 available: !deepSeekPlan.needsLogin)
                    self.lastUpdated = Date()
                    self.hasLoaded = true
                    self.isRefreshing = false
                    self.refreshing = false
                    self.updateWidgetSnapshot()
                }
            }
        }
    }

    var combinedDays: [DayUsage] {
        Self.combineDays(anthropic.snapshot.days, openAI.snapshot.days)
    }

    static func combineDays(_ a: [DayUsage], _ b: [DayUsage]) -> [DayUsage] {
        guard !b.isEmpty, b.contains(where: { $0.totals.cost > 0 }), a.count == b.count else {
            return a
        }
        return zip(a, b).map { d1, d2 in
            var d = DayUsage(day: d1.day)
            d.totals = d1.totals
            d.totals.absorb(d2.totals)
            return d
        }
    }

    var combinedTodayCost: Double {
        anthropic.snapshot.today.cost + openAI.snapshot.today.cost
    }

    // MARK: - Widget snapshot

    private var lastReloadFingerprint: WidgetSnapshot?

    func updateWidgetSnapshot() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: SettingsKeys.menuSections) ?? MenuSectionsConfig.storageDefault
        let showRemaining = (defaults.string(forKey: SettingsKeys.limitDisplay)
            ?? LimitDisplay.remaining.rawValue) != LimitDisplay.used.rawValue

        let sections = MenuSectionsConfig.parse(raw)
        var providers: [WSProvider] = []
        for section in sections where section.visible {
            switch section.id {
            case .claude: providers.append(wsProvider(anthropic))
            case .openai: if openAI.available { providers.append(wsProvider(openAI)) }
            case .openCode: if openCode.available { providers.append(wsProvider(openCode)) }
            case .deepSeek: if deepSeek.available { providers.append(wsProvider(deepSeek)) }
            case .week: break
            }
        }
        // Mirror the panel: only build the weekly bars if that section is on.
        let weekVisible = sections.contains { $0.id == .week && $0.visible }

        let days = Array(combinedDays.suffix(7))
        let maxCost = days.map(\.totals.cost).max() ?? 0
        let bars = weekVisible ? days.map { maxCost > 0 ? $0.totals.cost / maxCost : 0 } : []
        let weekCost = days.reduce(0) { $0 + $1.totals.cost }
        let weekTitle = "\(openAI.available ? L.t("last_7_days_total") : L.t("last_7_days")) — \(Formatters.cost(weekCost))"

        let snapshot = WidgetSnapshot(
            providers: providers,
            showRemaining: showRemaining,
            weekTitle: weekTitle,
            weekBars: bars,
            updatedText: Formatters.time(lastUpdated),
            date: lastUpdated
        )
        WidgetShared.save(snapshot)
        // reloadAllTimelines() is budgeted by WidgetKit (tens of reloads per
        // day); calling it on every 60 s cycle starves the repaints that
        // matter. Reload only when something the widget shows has changed —
        // countdown/cost freshness rides the timeline's 30-minute policy.
        let fingerprint = snapshot.reloadFingerprint
        if fingerprint != lastReloadFingerprint {
            lastReloadFingerprint = fingerprint
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func wsProvider(_ data: ProviderData) -> WSProvider {
        let gauges = data.menuGauges.map {
            WSGauge(label: $0.label,
                    used: min(max($0.utilization, 0), 100),
                    reset: $0.resetsAt.map(Formatters.resetCompact))
        }
        var lines: [String] = []
        if data.kind.hasLocalUsage {
            let today = data.snapshot.today
            lines.append("\(L.t("today")) \(Formatters.cost(today.cost)) · \(Formatters.tokens(today.totalTokens)) tokens")
        }
        if data.kind == .deepSeek, let balance = data.plan.credits?.balance {
            lines.append("\(L.t("balance")) \(Formatters.money(balance) ?? balance)")
        }
        return WSProvider(name: data.kind.name,
                          colorHex: data.kind.colorHex,
                          subscription: data.plan.subscription,
                          gauges: gauges,
                          lines: lines,
                          limitReached: data.plan.limitReachedReason)
    }
}

extension TokenTotals {
    mutating func absorb(_ other: TokenTotals) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite5m += other.cacheWrite5m
        cacheWrite1h += other.cacheWrite1h
        cost += other.cost
        messages += other.messages
    }
}
