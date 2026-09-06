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

    /// `proactiveWindow`: renew the token ahead of time while at least that
    /// much is left — apps pass hours so their extensions (which pass 0) almost
    /// never have to refresh themselves. See TokenPolicy.
    public static func fetch(proactiveWindow: TimeInterval = 0,
                             completion: @escaping (PlanStatus) -> Void) {
        resolveToken(proactiveWindow: proactiveWindow, rejectedToken: nil) { token, problem, needsLogin in
            guard let token else {
                completion(PlanStatus(gauges: [], error: problem ?? L.t("no_session"),
                                      needsLogin: needsLogin))
                return
            }
            requestUsage(token: token) { usageStatus in
                guard usageStatus.rejected else {
                    requestProfile(token: token, base: usageStatus.status, completion: completion)
                    return
                }
                // 401 before the local expiry: the provider dropped this access
                // token early. Refresh THIS token once and retry, instead of
                // telling the user to sign in again for hours.
                resolveToken(proactiveWindow: 0, rejectedToken: token) { retryToken, problem, needsLogin in
                    guard let retryToken else {
                        completion(PlanStatus(gauges: [], error: problem ?? L.t("no_session"),
                                              needsLogin: needsLogin))
                        return
                    }
                    requestUsage(token: retryToken) { retried in
                        requestProfile(token: retryToken, base: retried.status, completion: completion)
                    }
                }
            }
        }
    }

    /// Hands back a usable access token, refreshing under the cross-process
    /// lock when TokenPolicy says so. `rejectedToken` is an access token a
    /// usage endpoint just refused: it is refreshed regardless of its expiry
    /// unless another process already replaced it.
    private static func resolveToken(proactiveWindow: TimeInterval, rejectedToken: String?,
                                     _ done: @escaping (_ token: String?, _ problem: String?, _ needsLogin: Bool) -> Void) {
        guard let own = AnthropicTokenStore.load() else {
            done(nil, L.t("no_session_sign_in_with_your"), true)
            return
        }
        let rejected = rejectedToken == own.accessToken
        if !TokenPolicy.shouldRefresh(expiresAt: own.expiresAt, proactiveWindow: proactiveWindow,
                                      rejected: rejected) {
            done(own.accessToken, nil, false)   // fast path — no lock needed
            return
        }
        let stillUsable = !rejected && TokenPolicy.isUsable(expiresAt: own.expiresAt)
        guard own.refreshToken != nil else {
            stillUsable ? done(own.accessToken, nil, false)
                        : done(nil, L.t("session_expired_sign_in_again"), true)
            return
        }
        // Serialize the refresh across the app and its extension so two
        // processes never spend the same (single-use) refresh token.
        DispatchQueue.global(qos: .userInitiated).async {
            let lock = TokenRefreshLock.acquire(AnthropicTokenStore.service)
            // Re-read after acquiring: another process may have just refreshed.
            guard let current = AnthropicTokenStore.load() else {
                TokenRefreshLock.release(lock)
                done(nil, L.t("session_expired_sign_in_again"), true)
                return
            }
            let currentRejected = rejectedToken == current.accessToken
            if !TokenPolicy.shouldRefresh(expiresAt: current.expiresAt, proactiveWindow: proactiveWindow,
                                          rejected: currentRejected) {
                TokenRefreshLock.release(lock)
                done(current.accessToken, nil, false)
                return
            }
            let currentUsable = !currentRejected && TokenPolicy.isUsable(expiresAt: current.expiresAt)
            guard let rt = current.refreshToken else {
                TokenRefreshLock.release(lock)
                currentUsable ? done(current.accessToken, nil, false)
                              : done(nil, L.t("session_expired_sign_in_again"), true)
                return
            }
            AnthropicOAuth.refresh(refreshToken: rt) { creds, error in
                if let creds { AnthropicTokenStore.save(creds) }
                TokenRefreshLock.release(lock)
                if let creds {
                    done(creds.accessToken, nil, false)
                } else if currentUsable {
                    // A proactive renewal failed but the current token still
                    // works: use it and try again next cycle.
                    done(current.accessToken, nil, false)
                } else if OAuthError.isAuthFailure(error) {
                    // Only this device refreshes this token family, so a
                    // rejected refresh token is a genuinely dead session.
                    done(nil, L.t("session_expired_sign_in_again"), true)
                } else {
                    // Transient (network / server) failure: keep the session
                    // and retry next cycle instead of forcing a re-login.
                    done(nil, error ?? L.t("no_session"), false)
                }
            }
        }
    }

    private struct UsageResult {
        var status: PlanStatus
        /// The access token was refused (401) — distinct from any other error.
        var rejected = false
    }

    private static func requestUsage(token: String, completion: @escaping (UsageResult) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            var result = UsageResult(status: PlanStatus())
            defer { completion(result) }
            if let err {
                result.status.error = err.localizedDescription
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                result.status.error = L.t("invalid_response")
                return
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 401 {
                    result.status.error = L.t("unauthorized_sign_in_again")
                    result.status.needsLogin = true
                    result.rejected = true
                } else {
                    result.status.error = "HTTP \(http.statusCode)"
                }
                return
            }
            guard let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.status.error = L.t("unexpected_json")
                return
            }
            result.status.gauges = gauges(from: obj)
            if let extra = obj["extra_usage"] as? [String: Any],
               (extra["is_enabled"] as? NSNumber)?.boolValue == true {
                let eu = ExtraUsage(
                    utilization: (extra["utilization"] as? NSNumber)?.doubleValue,
                    usedCredits: (extra["used_credits"] as? NSNumber)?.doubleValue,
                    monthlyLimit: (extra["monthly_limit"] as? NSNumber)?.doubleValue)
                if eu.utilization != nil || eu.usedCredits != nil || eu.monthlyLimit != nil {
                    result.status.extraUsage = eu
                }
            }
            if result.status.gauges.isEmpty && !result.status.hasExtras {
                result.status.error = L.t("no_limit_data")
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

    static func gauges(from obj: [String: Any]) -> [PlanGauge] {
        var found: [String: PlanGauge] = [:]

        func scan(_ dict: [String: Any], depth: Int) {
            for (key, value) in dict {
                if key == "extra_usage" { continue }
                guard let v = value as? [String: Any] else { continue }
                if let u = v["utilization"] as? NSNumber {
                    let resets = parseDate(v["resets_at"])
                    // Unknown keys still surface — that's how new limits like
                    // seven_day_opus appeared without a code change — but only
                    // with some sign of life. The endpoint also ships dormant
                    // experiment buckets under internal codenames
                    // ("nimbus_quill": utilization 0, no reset, no dollars),
                    // and those rendered as a meaningless "Nimbus Quill" gauge.
                    let known = knownLabels.first(where: { $0.0 == key })?.1
                    if known == nil {
                        let hasDollars = v["limit_dollars"] as? NSNumber != nil
                            || v["used_dollars"] as? NSNumber != nil
                        guard u.doubleValue > 0 || resets != nil || hasDollars else { continue }
                    }
                    found[key] = PlanGauge(key: key, label: known ?? prettify(key),
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
