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

// Fitness-rings style: outer ring = session (5 h), inner ring = weekly, both
// filled with the value the host app dictates (remaining or used) for the
// first provider in the snapshot.
struct RingsView: View {
    let entry: WatchEntry

    var body: some View {
        let provider = entry.snapshot.providers.first
        let showRemaining = entry.snapshot.showRemaining
        ZStack {
            AccessoryWidgetBackground()
            if let provider, !provider.gauges.isEmpty {
                let color = Color(hex: provider.colorHex)
                if let session = provider.gauges.first {
                    ring(session, color: color, showRemaining: showRemaining)
                        .padding(3)
                }
                if provider.gauges.count > 1 {
                    ring(provider.gauges[1], color: color.opacity(0.55), showRemaining: showRemaining)
                        .padding(10)
                }
            } else {
                // No data (signed out, never synced…): just the mark, no rings.
                Image(systemName: "asterisk")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#D97757"))
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private func ring(_ gauge: WSGauge, color: Color, showRemaining: Bool) -> some View {
        let used = min(max(gauge.used, 0), 100)
        let shown = showRemaining ? 100 - used : used
        return ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 5)
            // At exactly 0 the ring must be EMPTY (limit exhausted is the one
            // moment it must not lie); any non-zero value keeps a visible nub.
            if shown > 0 {
                Circle()
                    .trim(from: 0, to: max(0.02, shown / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
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
