//
//  Components.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI

extension ProviderKind {
    var color: Color {
        switch self {
        case .anthropic: return Color(red: 0.851, green: 0.467, blue: 0.341)
        case .openAI: return Color(red: 0.063, green: 0.639, blue: 0.498)
        case .openCode: return Color(red: 0.545, green: 0.486, blue: 0.965)
        case .deepSeek: return Color(red: 0.302, green: 0.420, blue: 0.996)
        }
    }
}

struct GaugeRow: View {
    let gauge: PlanGauge
    var tint: Color = .accentColor
    @AppStorage(SettingsKeys.limitDisplay) private var limitDisplay = LimitDisplay.remaining.rawValue

    var body: some View {
        let used = min(max(gauge.utilization, 0), 100)
        let showRemaining = limitDisplay != LimitDisplay.used.rawValue
        let shown = showRemaining ? 100 - used : used
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(shown.rounded())) % \(showRemaining ? L.t("left") : L.t("used_2"))")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
            }
            ProgressView(value: shown, total: 100)
                .tint(color(used: used))
            if let resets = gauge.resetsAt {
                Text(Formatters.resetDescription(resets))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func color(used: Double) -> Color {
        switch used {
        case 90...: return .red
        case 70..<90: return .orange
        default: return tint
        }
    }
}

struct MoneyLimitRow: View {
    let label: String
    let usedPercent: Double?
    let usedText: String?
    let limitText: String?
    var resetsAt: Date? = nil
    var tint: Color = .accentColor
    @AppStorage(SettingsKeys.limitDisplay) private var limitDisplay = LimitDisplay.remaining.rawValue

    var body: some View {
        let showRemaining = limitDisplay != LimitDisplay.used.rawValue
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(amountText(showRemaining: showRemaining))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
            }
            if let used = usedPercent {
                let clamped = min(max(used, 0), 100)
                ProgressView(value: showRemaining ? 100 - clamped : clamped, total: 100)
                    .tint(color(used: clamped))
            }
            if let resets = resetsAt {
                Text(Formatters.resetDescription(resets))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func amountText(showRemaining: Bool) -> String {
        switch (usedText, limitText) {
        case let (u?, l?): return "\(u) \(L.t("of")) \(l)"
        case let (u?, nil): return u
        case let (nil, l?): return "\(L.t("limit_2")) \(l)"
        default:
            guard let p = usedPercent else { return "" }
            let clamped = min(max(p, 0), 100)
            let shown = showRemaining ? 100 - clamped : clamped
            return "\(Int(shown.rounded())) % \(showRemaining ? L.t("left") : L.t("used_2"))"
        }
    }

    private func color(used: Double) -> Color {
        switch used {
        case 90...: return .red
        case 70..<90: return .orange
        default: return tint
        }
    }
}

struct LimitBanner: View {
    let reason: String

    var body: some View {
        Label(String(format: L.t("limit_reached"), reason), systemImage: "exclamationmark.octagon.fill")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PlanExtrasView: View {
    let plan: PlanStatus
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let extra = plan.extraUsage {
                MoneyLimitRow(label: L.t("extra_usage_month"),
                              usedPercent: extra.utilization,
                              usedText: Formatters.money(extra.usedCredits),
                              limitText: Formatters.money(extra.monthlyLimit),
                              tint: tint)
            }
            if let credits = plan.credits {
                HStack(alignment: .firstTextBaseline) {
                    Text(L.t("credits"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(credits.unlimited ? L.t("unlimited") : (Formatters.money(credits.balance) ?? "—"))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.semibold)
                }
            }
            if let spend = plan.spendLimit {
                MoneyLimitRow(label: L.t("spending_limit"),
                              usedPercent: spend.usedPercent,
                              usedText: Formatters.money(spend.usedText),
                              limitText: Formatters.money(spend.limitText),
                              resetsAt: spend.resetsAt,
                              tint: tint)
            }
        }
    }
}

struct DayBars: View {
    let days: [DayUsage]
    var tint: Color = .accentColor

    var body: some View {
        let maxCost = max(days.map(\.totals.cost).max() ?? 0, 0.01)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(days) { d in
                let isToday = Calendar.current.isDateInToday(d.day)
                let isMax = d.totals.cost >= maxCost - 0.0001 && d.totals.cost > 0
                VStack(spacing: 3) {
                    Text(isToday || isMax ? Formatters.cost(d.totals.cost) : " ")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(d.totals.cost > 0
                              ? tint.opacity(isToday ? 1 : 0.55)
                              : Color.secondary.opacity(0.15))
                        .frame(height: max(3, CGFloat(d.totals.cost / maxCost) * 52))
                    Text(Formatters.dayShort(d.day))
                        .font(.system(size: 8))
                        .foregroundStyle(isToday ? .secondary : .tertiary)
                }
                .frame(maxWidth: .infinity)
                .help("\(Formatters.dayMedium(d.day)) — \(Formatters.cost(d.totals.cost)) · \(Formatters.tokens(d.totals.totalTokens)) tokens · \(d.totals.messages) \(L.t("messages_2"))")
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct DailyRow: View {
    let day: DayUsage
    let maxCost: Double
    var tint: Color = .accentColor

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day.day)
        HStack(spacing: 10) {
            Text(Formatters.dayMedium(day.day))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isToday ? .primary : .secondary)
                .frame(width: 76, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(isToday ? 1 : 0.7))
                        .frame(width: max(day.totals.cost > 0 ? 3 : 0,
                                          geo.size.width * CGFloat(day.totals.cost / max(maxCost, 0.001))))
                }
            }
            .frame(height: 10)
            Text(Formatters.cost(day.totals.cost))
                .font(.caption.monospacedDigit())
                .frame(width: 62, alignment: .trailing)
            Text(Formatters.tokens(day.totals.totalTokens))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .trailing)
        }
        .help("\(day.totals.messages) \(L.t("messages_2")) · \(L.t("input_2")) \(Formatters.tokens(day.totals.input)) · \(L.t("output_2")) \(Formatters.tokens(day.totals.output)) · \(L.t("cache_2")) \(Formatters.tokens(day.totals.cacheRead + day.totals.cacheWrite))")
    }
}
