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
    public var note: String? = nil     // status note: signed out, fetch failed…
    public var health: PlatformHealth? = nil   // platform incident status, when known

    public init(name: String, colorHex: String, subscription: String?,
                gauges: [WSGauge], lines: [String], limitReached: String?,
                note: String? = nil, health: PlatformHealth? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.subscription = subscription
        self.gauges = gauges
        self.lines = lines
        self.limitReached = limitReached
        self.note = note
        self.health = health
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

    // How long ago this snapshot was produced.
    public var age: TimeInterval { Date().timeIntervalSince(date) }

    /// Nothing to show — no provider holds a session on this device. Written
    /// in place of a stale snapshot so the widget/complication shows that
    /// state instead of freezing on the last numbers it ever saw.
    public static func empty() -> WidgetSnapshot {
        WidgetSnapshot(providers: [], showRemaining: true, weekTitle: "",
                       weekBars: [], updatedText: "", date: Date())
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
                // The countdown VALUE churns every minute, but whether a reset
                // label exists at all is rendered content (the 5-hour window
                // only has one while a session is active) — keep the presence,
                // drop the text.
                g.reset = g.reset == nil ? nil : ""
                return g
            }
            return p
        }
        return copy
    }

    /// The fingerprint as a token that is stable ACROSS processes and launches,
    /// so the host app can compare what it wants drawn against what the
    /// extension actually drew. `hashValue` cannot be used for this: Swift
    /// seeds string hashing per launch, so it differs between the app and the
    /// widget process for identical content.
    var reloadDigest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(reloadFingerprint) else { return "" }
        // FNV-1a: no dependency, deterministic everywhere, and collisions here
        // only cost a missed repaint until the next content change.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

/// Where the content a widget drew came from — the one thing that is invisible
/// from outside the extension when a complication refuses to move.
public enum WidgetRenderSource: String, Codable {
    case appSnapshot    // reused the host app's snapshot (the normal path)
    case selfFetched    // the app's snapshot was stale, so the extension fetched
    case fallback       // its own fetch timed out → last known snapshot
    case placeholder    // nothing to show: no snapshot AND no credentials
}

/// The three entry points WidgetKit drives in an extension. Which of them has
/// EVER run is the decisive diagnostic for a dead complication: the gallery
/// preview comes from `placeholder`/`getSnapshot` (synchronous, no network),
/// the face render from `getTimeline`. A blank preview with zero placeholder
/// pings means chronod is not launching the extension at all — no code path
/// of ours can cause that; it is registration/throttling state on the device.
public enum WidgetPhase: String, Codable, CaseIterable {
    case placeholder, snapshot, timeline
}

public struct WidgetPing: Codable, Hashable {
    public var count: Int
    public var last: Date

    public var age: TimeInterval { Date().timeIntervalSince(last) }
}

/// What a widget/complication last handed to WidgetKit. Written by the
/// extension, read by the app: the only way to tell "WidgetKit never ran my
/// extension" from "it ran and drew the wrong thing".
public struct WidgetRenderRecord: Codable, Hashable {
    public var date: Date
    public var digest: String
    public var providerCount: Int
    public var source: WidgetRenderSource

    public var age: TimeInterval { Date().timeIntervalSince(date) }
}

public enum WidgetShared {
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    public static var fileURL: URL? {
        containerURL?.appendingPathComponent("snapshot.json")
    }

    /// Where the extension records the digest of what it last rendered.
    private static var renderedURL: URL? {
        containerURL?.appendingPathComponent("rendered.txt")
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        // A cleaner utility can delete the whole group container while the app
        // is running — it happened, and every write after it failed silently,
        // freezing the macOS widget for days while the menu bar stayed fresh.
        // Recreate the directory rather than assume the system keeps it alive.
        write(data, to: url)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Called by a widget/complication from `getTimeline`: records the content
    /// it just handed to WidgetKit.
    ///
    /// Requesting a reload is not the same as getting one — WidgetKit silently
    /// drops requests once the daily budget is spent. The stores used to record
    /// the request as if it had been honoured, so a dropped one was never
    /// retried and the complication kept the old render until the numbers moved
    /// again. This is the acknowledgement that closes that loop.
    public static func recordRendered(_ snapshot: WidgetSnapshot,
                                      source: WidgetRenderSource = .appSnapshot) {
        guard let url = renderedURL,
              let data = try? JSONEncoder().encode(
                WidgetRenderRecord(date: Date(), digest: snapshot.reloadDigest,
                                   providerCount: snapshot.providers.count, source: source))
        else { return }
        write(data, to: url)
    }

    /// What the extension last rendered, or nil if it never ran — which is
    /// itself the answer when a complication will not move.
    public static func lastRender() -> WidgetRenderRecord? {
        guard let url = renderedURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetRenderRecord.self, from: data)
    }

    /// Digest of what the extension last rendered, or nil if it never ran (or
    /// the container was wiped) — which counts as "does not match", so the app
    /// asks for a reload.
    public static func renderedDigest() -> String? { lastRender()?.digest }

    // MARK: - Phase pings

    private static var pingsURL: URL? {
        containerURL?.appendingPathComponent("pings.json")
    }

    /// Marks that WidgetKit invoked the given entry point. Diagnostics only:
    /// a lost update under concurrent writes costs one count, never a wrong
    /// conclusion — the question these answer is "has this phase EVER run,
    /// and when was the last time".
    public static func recordPing(_ phase: WidgetPhase) {
        guard let url = pingsURL else { return }
        var all = pings()
        let previous = all[phase]
        all[phase] = WidgetPing(count: (previous?.count ?? 0) + 1, last: Date())
        let raw = Dictionary(uniqueKeysWithValues: all.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        write(data, to: url)
    }

    public static func pings() -> [WidgetPhase: WidgetPing] {
        guard let url = pingsURL, let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: WidgetPing].self, from: data)
        else { return [:] }
        var out: [WidgetPhase: WidgetPing] = [:]
        for (key, value) in raw {
            if let phase = WidgetPhase(rawValue: key) { out[phase] = value }
        }
        return out
    }

    private static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
