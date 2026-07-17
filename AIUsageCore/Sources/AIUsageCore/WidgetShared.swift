//
//  WidgetShared.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Data shared between the main app and the widget extension via the App Group container.
// The app writes a display-ready snapshot after each refresh; the widget only renders it.

public let appGroupIdentifier = "group.dev.aitor.ai-usage"

public struct WSGauge: Codable, Hashable {
    public var label: String
    public var used: Double            // 0...100, percentage consumed
    public var reset: String? = nil    // compact "resets in…" text, when known

    public init(label: String, used: Double, reset: String? = nil) {
        self.label = label
        self.used = used
        self.reset = reset
    }
}

public struct WSProvider: Codable, Hashable {
    public var name: String
    public var colorHex: String        // "#RRGGBB"
    public var subscription: String?
    public var gauges: [WSGauge]
    public var lines: [String]         // ready-to-show detail lines (cost, tokens, balance…)
    public var limitReached: String?

    public init(name: String, colorHex: String, subscription: String?,
                gauges: [WSGauge], lines: [String], limitReached: String?) {
        self.name = name
        self.colorHex = colorHex
        self.subscription = subscription
        self.gauges = gauges
        self.lines = lines
        self.limitReached = limitReached
    }
}

public struct WidgetSnapshot: Codable, Hashable {
    public var providers: [WSProvider]
    public var showRemaining: Bool     // true → show "% left", false → "% used"
    public var weekTitle: String
    public var weekBars: [Double]      // normalized 0...1
    public var updatedText: String
    public var date: Date

    public init(providers: [WSProvider], showRemaining: Bool, weekTitle: String,
                weekBars: [Double], updatedText: String, date: Date) {
        self.providers = providers
        self.showRemaining = showRemaining
        self.weekTitle = weekTitle
        self.weekBars = weekBars
        self.updatedText = updatedText
        self.date = date
    }

    public static let placeholder = WidgetSnapshot(
        providers: [
            WSProvider(name: "Claude", colorHex: "#D97757", subscription: nil,
                       gauges: [WSGauge(label: L.t("session_5_h"), used: 37),
                                WSGauge(label: L.t("week"), used: 13)],
                       lines: [], limitReached: nil),
            WSProvider(name: "OpenAI", colorHex: "#10A37F", subscription: nil,
                       gauges: [WSGauge(label: L.t("session_5_h"), used: 52)], lines: [], limitReached: nil),
        ],
        showRemaining: true,
        weekTitle: L.t("last_7_days"),
        weekBars: [0.3, 0.5, 0.9, 0.4, 0.7, 0.6, 0.8],
        updatedText: "",
        date: Date(timeIntervalSince1970: 0)
    )
}

public extension WidgetSnapshot {
    /// What the widget must repaint promptly: the display mode and the gauges
    /// at the integer granularity they render with. Timestamps, reset
    /// countdowns, cost lines and week bars churn on every refresh cycle and
    /// ride the widget's own timeline policy instead, so they are stripped
    /// here — reloading for them would burn WidgetKit's daily reload budget.
    var reloadFingerprint: WidgetSnapshot {
        var copy = self
        copy.updatedText = ""
        copy.date = Date(timeIntervalSince1970: 0)
        copy.weekTitle = ""
        copy.weekBars = []
        copy.providers = providers.map { provider in
            var p = provider
            p.lines = []
            p.gauges = provider.gauges.map { gauge in
                var g = gauge
                g.used = g.used.rounded()
                g.reset = nil
                return g
            }
            return p
        }
        return copy
    }
}

public enum WidgetShared {
    public static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("snapshot.json")
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
