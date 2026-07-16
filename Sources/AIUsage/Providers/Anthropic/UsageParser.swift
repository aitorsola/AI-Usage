//
//  UsageParser.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

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
