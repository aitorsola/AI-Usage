//
//  DemoData.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Fabricated, privacy-safe data used only for screenshots / showcasing the app.
// Nothing here reflects any real account. Activate with:
//   open -n "/Applications/AI Usage.app" --args -demo YES
enum DemoData {
    struct Bundle {
        let anthropic: ProviderData
        let openAI: ProviderData
        let openCode: ProviderData
        let deepSeek: ProviderData
    }

    static func make(now: Date = Date()) -> Bundle {
        Bundle(anthropic: claude(now: now),
               openAI: openai(now: now),
               openCode: opencode(now: now),
               deepSeek: deepseek())
    }

    // MARK: - Builders

    private static func totals(cost: Double, messages: Int,
                               input: Int, output: Int, cache: Int) -> TokenTotals {
        var t = TokenTotals()
        t.cost = cost
        t.messages = messages
        t.input = input
        t.output = output
        t.cacheRead = cache
        return t
    }

    private static func days(_ pattern: [Double], now: Date) -> [DayUsage] {
        let cal = Calendar.current
        return pattern.enumerated().map { i, cost in
            let day = cal.date(byAdding: .day, value: -(pattern.count - 1 - i), to: now) ?? now
            return DayUsage(day: day,
                            totals: totals(cost: cost, messages: Int(cost * 12),
                                           input: Int(cost * 70_000),
                                           output: Int(cost * 26_000),
                                           cache: Int(cost * 320_000)))
        }
    }

    private static func claude(now: Date) -> ProviderData {
        var snap = UsageSnapshot()
        snap.today = totals(cost: 0.82, messages: 11, input: 58_000, output: 22_000, cache: 300_000)
        snap.last7 = totals(cost: 4.6, messages: 62, input: 380_000, output: 140_000, cache: 2_000_000)
        snap.last30 = totals(cost: 16.3, messages: 210, input: 1_300_000, output: 480_000, cache: 7_100_000)
        snap.days = days([0.3, 0.8, 0.2, 0.5, 1.1, 0.4, 0.1, 0.7, 1.3, 0.3, 0.2, 0.9, 0.6, 0.82], now: now)
        snap.models = [
            ModelUsage(model: "claude-sonnet-4-6", totals: totals(cost: 10.2, messages: 138, input: 850_000, output: 320_000, cache: 4_700_000)),
            ModelUsage(model: "claude-haiku-4-5", totals: totals(cost: 3.1, messages: 54, input: 260_000, output: 90_000, cache: 1_500_000)),
            ModelUsage(model: "claude-opus-4-8", totals: totals(cost: 3.0, messages: 18, input: 190_000, output: 70_000, cache: 900_000)),
        ]
        snap.currentBlock = BlockInfo(start: now.addingTimeInterval(-3 * 3600), lastActivity: now,
                                      totals: totals(cost: 0.24, messages: 3, input: 16_000, output: 6_000, cache: 90_000))
        snap.maxBlockCost = 1.5

        var plan = PlanStatus()
        plan.subscription = "pro"
        plan.gauges = [
            PlanGauge(key: "five_hour", label: L.t("session_5_h"), utilization: 0,
                      resetsAt: now.addingTimeInterval(2 * 3600 + 12 * 60)),
            PlanGauge(key: "seven_day", label: L.t("week"), utilization: 0,
                      resetsAt: now.addingTimeInterval(4 * 24 * 3600)),
        ]
        return ProviderData(kind: .anthropic, snapshot: snap, plan: plan, available: true)
    }

    private static func openai(now: Date) -> ProviderData {
        var snap = UsageSnapshot()
        snap.today = totals(cost: 0.12, messages: 3, input: 14_000, output: 6_000, cache: 28_000)
        snap.last7 = totals(cost: 0.7, messages: 18, input: 90_000, output: 38_000, cache: 180_000)
        snap.last30 = totals(cost: 2.4, messages: 64, input: 300_000, output: 130_000, cache: 600_000)
        snap.days = days([0.0, 0.1, 0.05, 0.0, 0.2, 0.1, 0.0, 0.1, 0.25, 0.05, 0.0, 0.15, 0.1, 0.12], now: now)
        snap.models = [
            ModelUsage(model: "gpt-5", totals: totals(cost: 1.9, messages: 48, input: 240_000, output: 100_000, cache: 460_000)),
            ModelUsage(model: "gpt-5-mini", totals: totals(cost: 0.5, messages: 16, input: 60_000, output: 26_000, cache: 140_000)),
        ]

        var plan = PlanStatus()
        plan.subscription = "plus"
        plan.gauges = [
            PlanGauge(key: "primary", label: L.t("session_5_h"), utilization: 0,
                      resetsAt: now.addingTimeInterval(3 * 3600)),
            PlanGauge(key: "secondary", label: L.t("week"), utilization: 0,
                      resetsAt: now.addingTimeInterval(6 * 24 * 3600)),
        ]
        return ProviderData(kind: .openAI, snapshot: snap, plan: plan, available: true)
    }

    private static func opencode(now: Date) -> ProviderData {
        var snap = UsageSnapshot()
        snap.today = totals(cost: 0.2, messages: 4, input: 30_000, output: 12_000, cache: 96_000)
        snap.last7 = totals(cost: 0.9, messages: 20, input: 150_000, output: 60_000, cache: 420_000)
        snap.last30 = totals(cost: 3.1, messages: 66, input: 500_000, output: 200_000, cache: 1_300_000)
        snap.days = days([0.05, 0.1, 0.05, 0.1, 0.2, 0.1, 0.0, 0.15, 0.25, 0.05, 0.05, 0.15, 0.1, 0.2], now: now)
        snap.models = [
            ModelUsage(model: "anthropic/claude-sonnet-4-6", totals: totals(cost: 2.1, messages: 40, input: 320_000, output: 130_000, cache: 850_000)),
            ModelUsage(model: "openai/gpt-5", totals: totals(cost: 1.0, messages: 26, input: 180_000, output: 70_000, cache: 450_000)),
        ]
        return ProviderData(kind: .openCode, snapshot: snap, plan: PlanStatus(), available: true)
    }

    private static func deepseek() -> ProviderData {
        var plan = PlanStatus()
        plan.credits = CreditsInfo(unlimited: false, balance: "5.00")
        return ProviderData(kind: .deepSeek, snapshot: UsageSnapshot(), plan: plan, available: true)
    }
}
