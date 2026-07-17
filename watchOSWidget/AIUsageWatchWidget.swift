//
//  AIUsageWatchWidget.swift
//  AI Usage (watchOS Widget)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import WidgetKit
import SwiftUI
import AIUsageCore

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

struct WatchEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WatchSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: Date(), snapshot: WidgetShared.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let entry = WatchEntry(date: Date(), snapshot: WidgetShared.load() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

// Fitness-rings style for the first provider: outer ring = session (5 h) in
// the provider's brand color, inner ring = weekly in neutral gray, and two
// tiny center percentages color-matched to their ring so there is no guessing
// which quota is which. Values follow the host-dictated remaining/used mode.
struct RingsView: View {
    let entry: WatchEntry

    // Weekly gets its own hue (not a dimmer brand color): the ring and its
    // center label share it, mirroring how session pairs with the brand color.
    private static let weeklyColor = Color(white: 0.78)

    var body: some View {
        let provider = entry.snapshot.providers.first
        let showRemaining = entry.snapshot.showRemaining
        ZStack {
            AccessoryWidgetBackground()
            if let provider, !provider.gauges.isEmpty {
                let sessionColor = Color(hex: provider.colorHex)
                let session = provider.gauges.first
                let weekly = provider.gauges.count > 1 ? provider.gauges[1] : nil
                if let session {
                    ring(session, color: sessionColor, showRemaining: showRemaining)
                        .padding(2)
                }
                if let weekly {
                    ring(weekly, color: Self.weeklyColor, showRemaining: showRemaining)
                        .padding(8)
                }
                VStack(spacing: -1) {
                    if let session {
                        percentText(session, showRemaining: showRemaining)
                            .foregroundStyle(sessionColor)
                    }
                    if let weekly {
                        percentText(weekly, showRemaining: showRemaining)
                            .foregroundStyle(Self.weeklyColor)
                    }
                }
                .padding(14)
            } else {
                // No data (signed out, never synced…): just the mark, no rings.
                Image(systemName: "asterisk")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#D97757"))
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private func shownValue(_ gauge: WSGauge, showRemaining: Bool) -> Double {
        let used = min(max(gauge.used, 0), 100)
        return showRemaining ? 100 - used : used
    }

    private func percentText(_ gauge: WSGauge, showRemaining: Bool) -> some View {
        Text("\(Int(shownValue(gauge, showRemaining: showRemaining).rounded()))%")
            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func ring(_ gauge: WSGauge, color: Color, showRemaining: Bool) -> some View {
        let shown = shownValue(gauge, showRemaining: showRemaining)
        return ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 4)
            // At exactly 0 the ring must be EMPTY (limit exhausted is the one
            // moment it must not lie); any non-zero value keeps a visible nub.
            if shown > 0 {
                Circle()
                    .trim(from: 0, to: max(0.02, shown / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct AIUsageWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageWatchWidget", provider: WatchSnapshotProvider()) { entry in
            RingsView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description(L.t("widget_description"))
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct AIUsageWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUsageWatchWidget()
    }
}
