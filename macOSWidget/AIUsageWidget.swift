//
//  AIUsageWidget.swift
//  AI Usage Widget
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import WidgetKit
import AIUsageCore
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(timeIntervalSince1970: 0), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(timeIntervalSince1970: 0),
                                 snapshot: WidgetShared.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snap = WidgetShared.load() ?? .placeholder
        let entry = SnapshotEntry(date: snap.date, snapshot: snap)
        // The app reloads timelines on every refresh; this is only a safety net.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: snap.date) ?? snap.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

private extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

struct GaugeBar: View {
    let gauge: WSGauge
    let showRemaining: Bool
    let tint: Color

    var body: some View {
        let used = min(max(gauge.used, 0), 100)
        let shown = showRemaining ? 100 - used : used
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(gauge.label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(shown.rounded()))%")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule().fill(tint)
                        .frame(width: max(3, geo.size.width * shown / 100))
                }
            }
            .frame(height: 5)
        }
    }
}

struct ProviderBlock: View {
    let provider: WSProvider
    let showRemaining: Bool
    let maxLines: Int

    private var tint: Color { Color(hex: provider.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(provider.name).font(.caption).fontWeight(.semibold)
                if let sub = provider.subscription {
                    Text(sub.capitalized)
                        .font(.system(size: 8))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(tint.opacity(0.18)))
                }
                Spacer()
            }
            if let reason = provider.limitReached {
                Text(reason).font(.system(size: 9)).foregroundStyle(.red).lineLimit(1)
            }
            ForEach(provider.gauges.prefix(2), id: \.self) { g in
                GaugeBar(gauge: g, showRemaining: showRemaining, tint: tint)
            }
            if maxLines > 0 {
                ForEach(provider.lines.prefix(maxLines), id: \.self) { line in
                    Text(line).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

struct WeekBars: View {
    let title: String
    let bars: [Double]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.5))
                        .frame(height: max(2, CGFloat(min(max(v, 0), 1)) * 22))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 22)
        }
    }
}

struct BigGauge: View {
    let gauge: WSGauge
    let showRemaining: Bool
    let tint: Color

    var body: some View {
        let used = min(max(gauge.used, 0), 100)
        let shown = showRemaining ? 100 - used : used
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(Int(shown.rounded()))%").font(.callout).fontWeight(.bold).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule().fill(tint).frame(width: max(3, geo.size.width * shown / 100))
                }
            }
            .frame(height: 7)
            if let reset = gauge.reset {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 8))
                    Text(reset).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(.tertiary)
            }
        }
    }
}

struct AIUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: smallView
            default: wideView
            }
        }
        // Clicking anywhere on the widget opens the app's dashboard window.
        .widgetURL(URL(string: "aiusage://dashboard"))
    }

    // Small: the primary provider's session + weekly usage.
    private var smallView: some View {
        let provider = snap.providers.first(where: { !$0.gauges.isEmpty }) ?? snap.providers.first
        let tint = Color(hex: provider?.colorHex ?? "#D97757")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "asterisk").font(.caption2).foregroundStyle(tint)
                Text(provider?.name ?? "AI Usage").font(.caption).fontWeight(.bold).lineLimit(1)
                Spacer()
            }
            if let provider, !provider.gauges.isEmpty {
                ForEach(provider.gauges.prefix(2), id: \.self) { g in
                    BigGauge(gauge: g, showRemaining: snap.showRemaining, tint: tint)
                }
            } else if let line = provider?.lines.first {
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Medium / large: the full dropdown mirror.
    private var wideView: some View {
        let isLarge = family == .systemLarge
        // Medium mirrors just the first panel provider; large mirrors them all.
        let shown = Array(snap.providers.prefix(isLarge ? snap.providers.count : 1))
        let maxLines = isLarge ? 2 : 1
        return VStack(alignment: .leading, spacing: isLarge ? 8 : 6) {
            HStack(spacing: 4) {
                Image(systemName: "asterisk").font(.caption2).foregroundStyle(Color(hex: "#D97757"))
                Text("AI Usage").font(.caption).fontWeight(.bold)
                Spacer()
                if !snap.updatedText.isEmpty {
                    Text(snap.updatedText).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            ForEach(shown, id: \.name) { p in
                ProviderBlock(provider: p, showRemaining: snap.showRemaining, maxLines: maxLines)
            }
            if isLarge, !snap.weekBars.isEmpty {
                Spacer(minLength: 0)
                WeekBars(title: snap.weekTitle, bars: snap.weekBars)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget

struct AIUsageWidget: Widget {
    let kind = "AIUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            AIUsageWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("AI Usage")
        .description("Uso de tus asistentes de IA de un vistazo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct AIUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUsageWidget()
    }
}
