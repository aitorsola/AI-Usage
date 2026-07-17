//
//  AIUsageiOSWidget.swift
//  AI Usage (iOS Widget)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import WidgetKit
import AIUsageCore
import SwiftUI

private extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

struct AIUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct AIUsageiOSProvider: TimelineProvider {
    func placeholder(in context: Context) -> AIUsageEntry {
        AIUsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (AIUsageEntry) -> Void) {
        completion(AIUsageEntry(date: Date(), snapshot: WidgetShared.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIUsageEntry>) -> Void) {
        let entry = AIUsageEntry(date: Date(), snapshot: WidgetShared.load() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct AIUsageiOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AIUsageEntry

    // Mirror the macOS widget: small & medium show the first provider (with its
    // session + weekly gauges); large shows every provider.
    private var providerCount: Int { family == .systemLarge ? entry.snapshot.providers.count : 1 }

    var body: some View {
        let providers = Array(entry.snapshot.providers.prefix(providerCount))
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 8) {
            if providers.isEmpty {
                Text("AI Usage").font(.headline)
                Text(L.t("not_signed_in")).font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(providers, id: \.name) { provider in
                    ProviderBlock(provider: provider,
                                  showRemaining: entry.snapshot.showRemaining,
                                  showReset: true,
                                  showLines: family != .systemSmall)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct ProviderBlock: View {
    let provider: WSProvider
    let showRemaining: Bool
    let showReset: Bool
    let showLines: Bool

    var body: some View {
        let color = Color(hex: provider.colorHex)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(provider.name).font(.caption.bold())
                if let sub = provider.subscription {
                    Text(sub.capitalized).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let reason = provider.limitReached {
                Text(reason).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
            if let note = provider.note {
                Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            // Both gauges — session (5h) and weekly — like the macOS widget.
            ForEach(Array(provider.gauges.enumerated()), id: \.offset) { _, gauge in
                gaugeRow(gauge, color: color)
            }
            if showLines {
                ForEach(provider.lines, id: \.self) { line in
                    Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func gaugeRow(_ gauge: WSGauge, color: Color) -> some View {
        let shown = showRemaining ? 100 - gauge.used : gauge.used
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(gauge.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(Int(shown.rounded()))%").font(.caption2.monospacedDigit().bold())
            }
            ProgressView(value: shown, total: 100).tint(color)
            if showReset, let reset = gauge.reset {
                Text(reset).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

struct AIUsageiOSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageiOSWidget", provider: AIUsageiOSProvider()) { entry in
            AIUsageiOSWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description(L.t("widget_description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct AIUsageiOSWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUsageiOSWidget()
    }
}
