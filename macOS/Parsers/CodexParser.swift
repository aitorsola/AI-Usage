//
//  CodexParser.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

final class CodexParser {
    struct RateSnapshot {
        let ts: Date
        let gauges: [PlanGauge]
        let planType: String?
    }

    struct Result {
        var events: [UsageEvent] = []
        var gauges: [PlanGauge] = []
        var planType: String?
        var installed = false
    }

    private struct FileCacheEntry {
        let mtime: Date
        let size: Int
        let events: [UsageEvent]
        let rates: RateSnapshot?
    }

    private var cache: [String: FileCacheEntry] = [:]

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    func collect(since cutoff: Date) -> Result {
        var result = Result()
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return result }
        result.installed = true

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        var liveKeys = Set<String>()
        var latestRates: RateSnapshot?

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = vals?.contentModificationDate ?? .distantPast
            let size = vals?.fileSize ?? 0
            guard mtime >= cutoff else { continue }

            let path = url.path
            liveKeys.insert(path)
            let entry: FileCacheEntry
            if let cached = cache[path], cached.mtime == mtime, cached.size == size {
                entry = cached
            } else {
                entry = Self.parseFile(url: url, cutoff: cutoff)
                cache[path] = entry
            }
            result.events.append(contentsOf: entry.events)
            if let rates = entry.rates, rates.ts > (latestRates?.ts ?? .distantPast) {
                latestRates = rates
            }
        }
        cache = cache.filter { liveKeys.contains($0.key) }

        if let rates = latestRates {
            result.planType = rates.planType
            result.gauges = rates.gauges.filter { ($0.resetsAt ?? .distantPast) > Date() }
        }
        return result
    }

    private static func parseFile(url: URL, cutoff: Date) -> FileCacheEntry {
        let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mtime = vals?.contentModificationDate ?? .distantPast
        let size = vals?.fileSize ?? 0

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return FileCacheEntry(mtime: mtime, size: size, events: [], rates: nil)
        }

        var events: [UsageEvent] = []
        var rates: RateSnapshot?
        var currentModel = "gpt-5"
        var lineNo = 0

        text.enumerateLines { line, _ in
            lineNo += 1
            if line.contains("\"model\""), line.contains("turn_context") || line.contains("session_meta") {
                if let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                   let payload = obj["payload"] as? [String: Any],
                   let model = payload["model"] as? String, !model.isEmpty {
                    currentModel = model
                }
                return
            }
            guard line.contains("\"token_count\"") else { return }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let tsRaw = obj["timestamp"] as? String,
                  let ts = isoFrac.date(from: tsRaw) ?? iso.date(from: tsRaw)
            else { return }

            if let rl = payload["rate_limits"] as? [String: Any] {
                let snapshot = rateSnapshot(from: rl, ts: ts)
                if snapshot.ts > (rates?.ts ?? .distantPast) { rates = snapshot }
            }

            guard ts >= cutoff,
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any]
            else { return }

            let input = intVal(last["input_tokens"])
            let cached = intVal(last["cached_input_tokens"])
            let output = intVal(last["output_tokens"])
            guard input + output > 0 else { return }

            let uncached = max(0, input - cached)
            let cost = Pricing.openAICost(model: currentModel, uncachedInput: uncached,
                                          cachedInput: cached, output: output)
            events.append(UsageEvent(
                key: "\(url.lastPathComponent)#\(lineNo)",
                ts: ts, model: currentModel,
                input: uncached, output: output, cacheRead: cached,
                cacheWrite5m: 0, cacheWrite1h: 0, cost: cost))
        }
        return FileCacheEntry(mtime: mtime, size: size, events: events, rates: rates)
    }

    private static func rateSnapshot(from rl: [String: Any], ts: Date) -> RateSnapshot {
        let parsed = RateLimitParsing.parse(rl)
        return RateSnapshot(ts: ts, gauges: parsed.gauges, planType: parsed.planType)
    }

    private static func intVal(_ v: Any?) -> Int {
        (v as? NSNumber)?.intValue ?? 0
    }
}
