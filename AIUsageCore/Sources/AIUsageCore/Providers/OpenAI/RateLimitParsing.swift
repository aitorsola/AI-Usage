//
//  RateLimitParsing.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Decodes the rate-limit payload OpenAI embeds both in Codex CLI session logs
// and in the ChatGPT usage endpoint, so it is shared by the macOS parser and
// the cross-platform network fetcher.
public enum RateLimitParsing {
    struct Parsed {
        var gauges: [PlanGauge] = []
        var planType: String?
        var credits: CreditsInfo?
        var spendLimit: SpendLimit?
        var limitReachedReason: String?
    }

    public static func parse(_ rl: [String: Any]) -> (gauges: [PlanGauge], planType: String?) {
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
            reasons.append(L.t("spending_cap_reached"))
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
            return L.t("workspace_owner_credits_depleted")
        }
        if k.contains("member"), k.contains("credit") {
            return L.t("your_workspace_credits_are_depleted")
        }
        if k.contains("owner") {
            return L.t("workspace_usage_limit_reached")
        }
        if k.contains("member") {
            return L.t("your_usage_limit_was_reached")
        }
        if k.contains("rate") || k.contains("limit") {
            return L.t("usage_limit_reached")
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
        case 0: return L.t("limit")
        case ..<600: return L.t("session") + " (\(max(1, minutes / 60)) h)"
        case 10080: return L.t("week")
        case 1440...: return "\(minutes / 1440) " + L.t("days")
        default: return "\(minutes / 60) h"
        }
    }
}
