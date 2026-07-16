import Foundation

final class UsageParser {
    private struct FileCacheEntry {
        let mtime: Date
        let size: Int
        let events: [UsageEvent]
    }

    private var cache: [String: FileCacheEntry] = [:]

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    func collectEvents(since cutoff: Date) -> [UsageEvent] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var events: [UsageEvent] = []
        var liveKeys = Set<String>()

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = vals?.contentModificationDate ?? .distantPast
            let size = vals?.fileSize ?? 0
            guard mtime >= cutoff else { continue }

            let path = url.path
            liveKeys.insert(path)
            if let cached = cache[path], cached.mtime == mtime, cached.size == size {
                events.append(contentsOf: cached.events)
                continue
            }
            let parsed = parseFile(url: url, cutoff: cutoff)
            cache[path] = FileCacheEntry(mtime: mtime, size: size, events: parsed)
            events.append(contentsOf: parsed)
        }

        cache = cache.filter { liveKeys.contains($0.key) }
        return events
    }

    private func parseFile(url: URL, cutoff: Date) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [UsageEvent] = []
        text.enumerateLines { line, _ in
            if let event = Self.parseLine(line, cutoff: cutoff) {
                out.append(event)
            }
        }
        return out
    }

    private static func parseLine(_ line: String, cutoff: Date) -> UsageEvent? {
        guard line.contains("\"assistant\""), line.contains("\"usage\"") else { return nil }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let tsRaw = obj["timestamp"] as? String
        else { return nil }

        let model = (msg["model"] as? String) ?? ""
        guard !model.isEmpty, model != "<synthetic>" else { return nil }
        guard let ts = isoFrac.date(from: tsRaw) ?? iso.date(from: tsRaw), ts >= cutoff else { return nil }

        let t = tokens(from: usage)
        guard t.input + t.output + t.read + t.w5m + t.w1h > 0 else { return nil }

        let mid = (msg["id"] as? String) ?? (obj["uuid"] as? String) ?? UUID().uuidString
        let rid = (obj["requestId"] as? String) ?? ""
        let cost = Pricing.cost(model: model, input: t.input, output: t.output,
                                cacheRead: t.read, w5m: t.w5m, w1h: t.w1h)
        return UsageEvent(key: mid + ":" + rid, ts: ts, model: model,
                          input: t.input, output: t.output, cacheRead: t.read,
                          cacheWrite5m: t.w5m, cacheWrite1h: t.w1h, cost: cost)
    }

    private static func intVal(_ v: Any?) -> Int {
        (v as? NSNumber)?.intValue ?? 0
    }

    private static func tokens(from usage: [String: Any]) -> (input: Int, output: Int, read: Int, w5m: Int, w1h: Int) {
        if let iterations = usage["iterations"] as? [[String: Any]], !iterations.isEmpty {
            var i = 0, o = 0, r = 0, w5 = 0, w1 = 0
            for it in iterations {
                i += intVal(it["input_tokens"])
                o += intVal(it["output_tokens"])
                r += intVal(it["cache_read_input_tokens"])
                if let cc = it["cache_creation"] as? [String: Any] {
                    w5 += intVal(cc["ephemeral_5m_input_tokens"])
                    w1 += intVal(cc["ephemeral_1h_input_tokens"])
                } else {
                    w5 += intVal(it["cache_creation_input_tokens"])
                }
            }
            return (i, o, r, w5, w1)
        }
        let i = intVal(usage["input_tokens"])
        let o = intVal(usage["output_tokens"])
        let r = intVal(usage["cache_read_input_tokens"])
        var w5 = 0, w1 = 0
        if let cc = usage["cache_creation"] as? [String: Any] {
            w5 = intVal(cc["ephemeral_5m_input_tokens"])
            w1 = intVal(cc["ephemeral_1h_input_tokens"])
        } else {
            w5 = intVal(usage["cache_creation_input_tokens"])
        }
        return (i, o, r, w5, w1)
    }
}

enum Aggregator {
    static func snapshot(from rawEvents: [UsageEvent], now: Date = Date()) -> UsageSnapshot {
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
