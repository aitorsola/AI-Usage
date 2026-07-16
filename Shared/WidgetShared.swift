import Foundation

// Data shared between the main app and the widget extension via the App Group container.
// The app writes a display-ready snapshot after each refresh; the widget only renders it.

let appGroupIdentifier = "group.dev.aitor.ai-usage"

struct WSGauge: Codable, Hashable {
    var label: String
    var used: Double            // 0...100, percentage consumed
    var reset: String? = nil    // compact "resets in…" text, when known
}

struct WSProvider: Codable, Hashable {
    var name: String
    var colorHex: String        // "#RRGGBB"
    var subscription: String?
    var gauges: [WSGauge]
    var lines: [String]         // ready-to-show detail lines (cost, tokens, balance…)
    var limitReached: String?
}

struct WidgetSnapshot: Codable, Hashable {
    var providers: [WSProvider]
    var showRemaining: Bool     // true → show "% left", false → "% used"
    var weekTitle: String
    var weekBars: [Double]      // normalized 0...1
    var updatedText: String
    var date: Date

    static let placeholder = WidgetSnapshot(
        providers: [
            WSProvider(name: "Claude", colorHex: "#D97757", subscription: nil,
                       gauges: [WSGauge(label: "Sesión", used: 37, reset: "2 h 30 min"),
                                WSGauge(label: "Semana", used: 13, reset: "mié 18 jul")],
                       lines: [], limitReached: nil),
            WSProvider(name: "OpenAI", colorHex: "#10A37F", subscription: nil,
                       gauges: [WSGauge(label: "Primary", used: 52)], lines: [], limitReached: nil),
        ],
        showRemaining: true,
        weekTitle: "Últimos 7 días",
        weekBars: [0.3, 0.5, 0.9, 0.4, 0.7, 0.6, 0.8],
        updatedText: "",
        date: Date(timeIntervalSince1970: 0)
    )
}

enum WidgetShared {
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("snapshot.json")
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
