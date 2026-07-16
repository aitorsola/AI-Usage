//
//  Formatters.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

enum Formatters {
    private static let costFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = .autoupdatingCurrent
        return f
    }()

    static func cost(_ v: Double) -> String {
        "$" + (costFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }

    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String.localizedStringWithFormat("%.1f B", d / 1_000_000_000)
        case 1_000_000...: return String.localizedStringWithFormat("%.1f M", d / 1_000_000)
        case 1_000...: return String.localizedStringWithFormat("%.0f k", d / 1_000)
        default: return "\(n)"
        }
    }

    static func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    static func remaining(until d: Date) -> String {
        let s = max(0, Int(d.timeIntervalSinceNow))
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    static func money(_ value: Double?) -> String? {
        value.map { cost($0) }
    }

    static func money(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = Double(raw) { return cost(d) }
        return raw
    }

    static func resetDescription(_ d: Date) -> String {
        if d.timeIntervalSinceNow < 24 * 3600 {
            return String(format: L.t("resets_in"),
                          remaining(until: d), time(d))
        }
        return String(format: L.t("resets_on_at"),
                      dayMedium(d), time(d))
    }

    // Short reset text for tight spaces (widget): countdown within a day, else the day.
    static func resetCompact(_ d: Date) -> String {
        d.timeIntervalSinceNow < 24 * 3600 ? remaining(until: d) : dayMedium(d)
    }

    private static let dayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private static let dayMediumFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    static func dayShort(_ d: Date) -> String {
        dayShortFormatter.string(from: d)
    }

    static func dayMedium(_ d: Date) -> String {
        dayMediumFormatter.string(from: d)
    }

    static func modelName(_ id: String) -> String {
        guard id.lowercased().hasPrefix("claude") else { return id }
        var parts = id.lowercased().split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        guard let family = parts.first else { return id }
        let numbers = parts.dropFirst().filter { $0.count < 6 && Int($0) != nil }
        let version = numbers.joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }
}
