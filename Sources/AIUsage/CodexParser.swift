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

enum RateLimitParsing {
    struct Parsed {
        var gauges: [PlanGauge] = []
        var planType: String?
        var credits: CreditsInfo?
        var spendLimit: SpendLimit?
        var limitReachedReason: String?
    }

    static func parse(_ rl: [String: Any]) -> (gauges: [PlanGauge], planType: String?) {
        let full = parseFull(rl)
        return (full.gauges, full.planType)
    }

    static func parseFull(_ rl: [String: Any]) -> Parsed {
        var out = Parsed()
        for key in ["primary", "secondary"] {
            guard let window = rl[key] as? [String: Any],
                  let used = window["used_percent"] as? NSNumber else { continue }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue ?? 0
            var resets = (window["resets_at"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue > 1_000_000_000_000
                     ? $0.doubleValue / 1000 : $0.doubleValue)
            }
            if resets == nil, let secs = window["resets_in_seconds"] as? NSNumber {
                resets = Date().addingTimeInterval(secs.doubleValue)
            }
            out.gauges.append(PlanGauge(key: key, label: windowLabel(minutes: minutes),
                                        utilization: used.doubleValue, resetsAt: resets))
        }
        out.planType = rl["plan_type"] as? String

        if let c = rl["credits"] as? [String: Any] {
            let unlimited = (c["unlimited"] as? NSNumber)?.boolValue ?? false
            let balance = (c["balance"] as? String)
                ?? (c["balance"] as? NSNumber).map { "\($0)" }
            if unlimited || balance != nil {
                out.credits = CreditsInfo(unlimited: unlimited, balance: balance)
            }
        }

        if let il = rl["individual_limit"] as? [String: Any],
           let limit = stringValue(il["limit"]),
           let used = stringValue(il["used"]) {
            let remaining = (il["remaining_percent"] as? NSNumber)?.doubleValue
            let resets = (il["resets_at"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue > 1_000_000_000_000
                     ? $0.doubleValue / 1000 : $0.doubleValue)
            }
            out.spendLimit = SpendLimit(limitText: limit, usedText: used,
                                        usedPercent: remaining.map { 100 - $0 },
                                        resetsAt: resets)
        }

        var reasons: [String] = []
        if let raw = rl["rate_limit_reached_type"] as? String, !raw.isEmpty {
            reasons.append(humanReason(raw))
        }
        if (rl["spend_control_reached"] as? NSNumber)?.boolValue == true {
            reasons.append(L.t("tope de gasto alcanzado", "spending cap reached"))
        }
        out.limitReachedReason = reasons.first
        return out
    }

    private static func stringValue(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber { return "\(n)" }
        return nil
    }

    private static func humanReason(_ raw: String) -> String {
        let k = raw.lowercased()
        if k.contains("owner"), k.contains("credit") {
            return L.t("créditos del propietario del workspace agotados", "workspace owner credits depleted")
        }
        if k.contains("member"), k.contains("credit") {
            return L.t("créditos de tu usuario del workspace agotados", "your workspace credits are depleted")
        }
        if k.contains("owner") {
            return L.t("límite de uso del workspace alcanzado", "workspace usage limit reached")
        }
        if k.contains("member") {
            return L.t("límite de uso de tu usuario alcanzado", "your usage limit was reached")
        }
        if k.contains("rate") || k.contains("limit") {
            return L.t("límite de uso alcanzado", "usage limit reached")
        }
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    static func findRateLimits(in obj: [String: Any]) -> [String: Any]? {
        if obj["primary"] != nil || obj["secondary"] != nil { return obj }
        for key in ["rate_limits", "rate_limit", "usage"] {
            if let d = obj[key] as? [String: Any],
               d["primary"] != nil || d["secondary"] != nil {
                return d
            }
        }
        for (_, value) in obj {
            if let d = value as? [String: Any],
               d["primary"] is [String: Any] || d["secondary"] is [String: Any] {
                return d
            }
        }
        return nil
    }

    static func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 0: return L.t("Límite", "Limit")
        case ..<600: return L.t("Sesión", "Session") + " (\(max(1, minutes / 60)) h)"
        case 10080: return L.t("Semana", "Week")
        case 1440...: return "\(minutes / 1440) " + L.t("días", "days")
        default: return "\(minutes / 60) h"
        }
    }
}
