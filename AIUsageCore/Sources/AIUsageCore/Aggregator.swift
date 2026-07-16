//
//  Aggregator.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Shared aggregation over raw usage events, used by every provider parser
// (Claude, Codex, OpenCode) to build a UsageSnapshot.
public enum Aggregator {
    public static func snapshot(from rawEvents: [UsageEvent], now: Date = Date()) -> UsageSnapshot {
        var seen = Set<String>()
        var events: [UsageEvent] = []
        events.reserveCapacity(rawEvents.count)
        for e in rawEvents.sorted(by: { $0.ts < $1.ts }) where seen.insert(e.key).inserted {
            events.append(e)
        }

        var snap = UsageSnapshot()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let start30 = cal.date(byAdding: .day, value: -29, to: todayStart)!
        let start7 = cal.date(byAdding: .day, value: -6, to: todayStart)!

        var daysDict: [Date: DayUsage] = [:]
        var modelsDict: [String: ModelUsage] = [:]

        for e in events {
            guard e.ts >= start30 else { continue }
            let day = cal.startOfDay(for: e.ts)
            daysDict[day, default: DayUsage(day: day)].totals.add(e)
            modelsDict[e.model, default: ModelUsage(model: e.model)].totals.add(e)
            snap.last30.add(e)
            if e.ts >= start7 { snap.last7.add(e) }
            if e.ts >= todayStart { snap.today.add(e) }
        }

        var days: [DayUsage] = []
        var d = start30
        while d <= todayStart {
            days.append(daysDict[d] ?? DayUsage(day: d))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        snap.days = days
        snap.models = modelsDict.values.sorted { $0.totals.cost > $1.totals.cost }

        var blocks: [BlockInfo] = []
        for e in events {
            if var last = blocks.last,
               e.ts < last.start.addingTimeInterval(5 * 3600),
               e.ts.timeIntervalSince(last.lastActivity) < 5 * 3600 {
                last.totals.add(e)
                last.lastActivity = max(last.lastActivity, e.ts)
                blocks[blocks.count - 1] = last
            } else {
                var block = BlockInfo(start: floorToHour(e.ts), lastActivity: e.ts)
                block.totals.add(e)
                blocks.append(block)
            }
        }
        snap.maxBlockCost = blocks.map(\.totals.cost).max() ?? 0
        if let last = blocks.last, now < last.end {
            snap.currentBlock = last
        }
        snap.lastUpdated = now
        return snap
    }

    private static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }
}
