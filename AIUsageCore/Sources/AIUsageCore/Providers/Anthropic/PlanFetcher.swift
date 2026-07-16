//
//  PlanFetcher.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import Security

public enum PlanFetcher {
    static let userAgent = "claude-code/2.1.207 (external, ai-usage)"

    public static func fetch(completion: @escaping (PlanStatus) -> Void) {
        resolveToken { token, subscription, problem, needsLogin in
            guard let token else {
                completion(PlanStatus(gauges: [], subscription: subscription,
                                      error: problem ?? L.t("no_session"),
                                      needsLogin: needsLogin))
                return
            }
            requestUsage(token: token, subscription: subscription) { usageStatus in
                requestProfile(token: token, base: usageStatus, completion: completion)
            }
        }
    }

    private static func resolveToken(_ done: @escaping (_ token: String?, _ subscription: String?, _ problem: String?, _ needsLogin: Bool) -> Void) {
        guard let own = AnthropicTokenStore.load() else {
            done(nil, nil, L.t("no_session_sign_in_with_your"), true)
            return
        }
        let stillValid = own.expiresAt.map { $0 > Date().addingTimeInterval(60) } ?? true
        if stillValid {
            done(own.accessToken, nil, nil, false)
            return
        }
        guard let rt = own.refreshToken else {
            done(nil, nil, L.t("session_expired_sign_in_again"), true)
            return
        }
        AnthropicOAuth.refresh(refreshToken: rt) { creds, _ in
            if let creds {
                done(creds.accessToken, nil, nil, false)
            } else {
                done(nil, nil, L.t("session_expired_sign_in_again"), true)
            }
        }
    }

    private static func requestUsage(token: String, subscription: String?,
                                     completion: @escaping (PlanStatus) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            var status = PlanStatus(subscription: subscription)
            defer { completion(status) }
            if let err {
                status.error = err.localizedDescription
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                status.error = L.t("invalid_response")
                return
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 401 {
                    status.error = L.t("unauthorized_sign_in_again")
                    status.needsLogin = true
                } else {
                    status.error = "HTTP \(http.statusCode)"
                }
                return
            }
            guard let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                status.error = L.t("unexpected_json")
                return
            }
            status.gauges = gauges(from: obj)
            if let extra = obj["extra_usage"] as? [String: Any],
               (extra["is_enabled"] as? NSNumber)?.boolValue == true {
                let eu = ExtraUsage(
                    utilization: (extra["utilization"] as? NSNumber)?.doubleValue,
                    usedCredits: (extra["used_credits"] as? NSNumber)?.doubleValue,
                    monthlyLimit: (extra["monthly_limit"] as? NSNumber)?.doubleValue)
                if eu.utilization != nil || eu.usedCredits != nil || eu.monthlyLimit != nil {
                    status.extraUsage = eu
                }
            }
            if status.gauges.isEmpty && !status.hasExtras {
                status.error = L.t("no_limit_data")
            }
        }.resume()
    }

    private static func requestProfile(token: String, base: PlanStatus,
                                       completion: @escaping (PlanStatus) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var status = base
            defer { completion(status) }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return }
            if let account = obj["account"] as? [String: Any] {
                status.accountEmail = (account["email"] as? String)
                    ?? (account["email_address"] as? String)
                status.accountName = (account["full_name"] as? String)
                    ?? (account["display_name"] as? String)
            }
            if let org = obj["organization"] as? [String: Any] {
                let rawType = (org["organization_type"] as? String)
                    ?? (org["billing_type"] as? String)
                if let rawType, status.subscription == nil {
                    status.subscription = prettySubscription(rawType)
                }
            }
        }.resume()
    }

    private static func prettySubscription(_ raw: String) -> String {
        raw.replacingOccurrences(of: "claude_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static let knownLabels: [(String, String)] = [
        ("five_hour", L.t("session_5_h")),
        ("seven_day", L.t("week")),
        ("seven_day_opus", L.t("opus_week")),
        ("seven_day_sonnet", L.t("sonnet_week")),
        ("seven_day_oauth_apps", L.t("apps_week")),
    ]

    private static func gauges(from obj: [String: Any]) -> [PlanGauge] {
        var found: [String: PlanGauge] = [:]

        func scan(_ dict: [String: Any], depth: Int) {
            for (key, value) in dict {
                if key == "extra_usage" { continue }
                guard let v = value as? [String: Any] else { continue }
                if let u = v["utilization"] as? NSNumber {
                    let resets = parseDate(v["resets_at"])
                    let label = knownLabels.first(where: { $0.0 == key })?.1 ?? prettify(key)
                    found[key] = PlanGauge(key: key, label: label,
                                           utilization: u.doubleValue, resetsAt: resets)
                } else if depth < 1 {
                    scan(v, depth: depth + 1)
                }
            }
        }
        scan(obj, depth: 0)

        var ordered: [PlanGauge] = []
        for (key, _) in knownLabels {
            if let g = found.removeValue(forKey: key) { ordered.append(g) }
        }
        ordered.append(contentsOf: found.values.sorted { $0.key < $1.key })
        return ordered
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    private static func parseDate(_ value: Any?) -> Date? {
        if let s = value as? String {
            return isoFrac.date(from: s) ?? iso.date(from: s)
        }
        if let n = value as? NSNumber {
            let v = n.doubleValue
            return Date(timeIntervalSince1970: v > 1_000_000_000_000 ? v / 1000 : v)
        }
        return nil
    }

    private static func prettify(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
