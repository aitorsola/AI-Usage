//
//  OpenAIAuth.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import CryptoKit
import Security

public enum OpenAIOAuth {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let redirect = "http://localhost:1455/auth/callback"
    static let authorizeEndpoint = "https://auth.openai.com/oauth/authorize"
    static let tokenEndpoint = "https://auth.openai.com/oauth/token"

    public struct Credentials {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresAt: Date?
        public let accountID: String?
        public let planType: String?
        public let email: String?
    }

    static func authorizeURL(verifier: String) -> URL {
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var comps = URLComponents(string: authorizeEndpoint)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "codex_cli_rs"),
            URLQueryItem(name: "state", value: verifier),
        ]
        return comps.url!
    }

    static func exchange(code: String, verifier: String,
                         completion: @escaping (Credentials?, String?) -> Void) {
        post(form: [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirect,
        ], fallbackAccountID: nil, fallbackRefresh: nil, fallbackEmail: nil, completion: completion)
    }

    static func refresh(refreshToken: String, accountID: String?, email: String? = nil,
                        completion: @escaping (Credentials?, String?) -> Void) {
        post(form: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ], fallbackAccountID: accountID, fallbackRefresh: refreshToken,
           fallbackEmail: email, completion: completion)
    }

    private static func post(form: [String: String], fallbackAccountID: String?,
                             fallbackRefresh: String?, fallbackEmail: String?,
                             completion: @escaping (Credentials?, String?) -> Void) {
        var req = URLRequest(url: URL(string: tokenEndpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value)"
        }.joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(nil, err.localizedDescription); return }
            guard let http = resp as? HTTPURLResponse, let data else {
                completion(nil, L.t("invalid_response")); return
            }
            guard http.statusCode == 200,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let access = obj["access_token"] as? String
            else {
                let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                completion(nil, "HTTP \(http.statusCode) \(detail)")
                return
            }
            let idToken = obj["id_token"] as? String
            let expires = (obj["expires_in"] as? NSNumber).map {
                Date().addingTimeInterval($0.doubleValue)
            }
            let creds = Credentials(
                accessToken: access,
                refreshToken: (obj["refresh_token"] as? String) ?? fallbackRefresh,
                expiresAt: expires ?? jwtExpiry(access),
                accountID: accountID(idToken: idToken, accessToken: access) ?? fallbackAccountID,
                planType: planType(idToken: idToken, accessToken: access),
                email: email(idToken: idToken, accessToken: access) ?? fallbackEmail)
            // Not stored here: the caller saves under its refresh lock (or
            // parks a watch grant under the watch service).
            completion(creds, nil)
        }.resume()
    }

    static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func jwtExpiry(_ token: String) -> Date? {
        (jwtClaims(token)?["exp"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue)
        }
    }

    static func accountID(idToken: String?, accessToken: String?) -> String? {
        for token in [idToken, accessToken].compactMap({ $0 }) {
            guard let claims = jwtClaims(token) else { continue }
            if let id = claims["chatgpt_account_id"] as? String { return id }
            if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
               let id = auth["chatgpt_account_id"] as? String { return id }
            if let orgs = claims["organizations"] as? [[String: Any]],
               let id = orgs.first?["id"] as? String { return id }
        }
        return nil
    }

    static func planType(idToken: String?, accessToken: String?) -> String? {
        for token in [idToken, accessToken].compactMap({ $0 }) {
            if let auth = jwtClaims(token)?["https://api.openai.com/auth"] as? [String: Any],
               let plan = auth["chatgpt_plan_type"] as? String {
                return plan
            }
        }
        return nil
    }

    static func email(idToken: String?, accessToken: String?) -> String? {
        for token in [idToken, accessToken].compactMap({ $0 }) {
            guard let claims = jwtClaims(token) else { continue }
            if let e = claims["email"] as? String { return e }
            if let profile = claims["https://api.openai.com/profile"] as? [String: Any],
               let e = profile["email"] as? String { return e }
        }
        return nil
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum OpenAITokenStore {
    /// This device's own session.
    public static let service = "AI Usage-openai-credentials"
    /// The Apple Watch's own session, parked on the iPhone only until the
    /// watch confirms it received it. Never refreshed from the phone.
    public static let watchService = "AI Usage-openai-credentials-watch"

    public static func load(service: String = service) -> OpenAIOAuth.Credentials? {
        guard let data = CredentialStore.load(service: service),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = obj["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let expires = (obj["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000)
        }
        return OpenAIOAuth.Credentials(accessToken: token,
                                       refreshToken: obj["refreshToken"] as? String,
                                       expiresAt: expires,
                                       accountID: obj["accountID"] as? String,
                                       planType: obj["planType"] as? String,
                                       email: obj["email"] as? String)
    }

    public static func save(_ creds: OpenAIOAuth.Credentials, service: String = service) {
        var payload: [String: Any] = ["accessToken": creds.accessToken]
        if let r = creds.refreshToken { payload["refreshToken"] = r }
        if let e = creds.expiresAt { payload["expiresAt"] = e.timeIntervalSince1970 * 1000 }
        if let a = creds.accountID { payload["accountID"] = a }
        if let p = creds.planType { payload["planType"] = p }
        if let m = creds.email { payload["email"] = m }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        CredentialStore.save(data, service: service)
    }

    public static func delete(service: String = service) {
        CredentialStore.delete(service: service)
    }
}

public enum CodexAuthFile {
    public static func load() -> OpenAIOAuth.Credentials? {
        #if !os(macOS)
        return nil   // iOS has no local Codex CLI auth file.
        #else
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty
        else { return nil }
        let idToken = tokens["id_token"] as? String
        return OpenAIOAuth.Credentials(
            accessToken: access,
            refreshToken: tokens["refresh_token"] as? String,
            expiresAt: OpenAIOAuth.jwtExpiry(access),
            accountID: (tokens["account_id"] as? String)
                ?? OpenAIOAuth.accountID(idToken: idToken, accessToken: access),
            planType: OpenAIOAuth.planType(idToken: idToken, accessToken: access),
            email: OpenAIOAuth.email(idToken: idToken, accessToken: access))
        #endif
    }
}

public enum OpenAIUsageFetcher {
    /// See PlanFetcher.fetch(proactiveWindow:) — same contract.
    public static func fetch(proactiveWindow: TimeInterval = 0,
                             completion: @escaping (PlanStatus) -> Void) {
        resolveCredentials(proactiveWindow: proactiveWindow, rejectedToken: nil) { creds, problem, needsLogin in
            guard let creds else {
                completion(PlanStatus(gauges: [], subscription: nil,
                                      error: problem, needsLogin: needsLogin))
                return
            }
            request(creds: creds) { result in
                guard result.rejected else { completion(result.status); return }
                // Refused before the local expiry: refresh this exact token
                // once and retry before reporting a dead session.
                resolveCredentials(proactiveWindow: 0, rejectedToken: creds.accessToken) { retry, problem, needsLogin in
                    guard let retry else {
                        completion(PlanStatus(gauges: [], subscription: nil,
                                              error: problem, needsLogin: needsLogin))
                        return
                    }
                    request(creds: retry) { completion($0.status) }
                }
            }
        }
    }

    private static func resolveCredentials(proactiveWindow: TimeInterval, rejectedToken: String?,
                                           _ done: @escaping (OpenAIOAuth.Credentials?, String?, Bool) -> Void) {
        guard let stored = OpenAITokenStore.load() ?? CodexAuthFile.load() else {
            done(nil, L.t("no_session_sign_in_with_your_2"), true)
            return
        }
        let rejected = rejectedToken == stored.accessToken
        if !TokenPolicy.shouldRefresh(expiresAt: stored.expiresAt, proactiveWindow: proactiveWindow,
                                      rejected: rejected) {
            done(stored, nil, false)   // fast path — no lock needed
            return
        }
        let stillUsable = !rejected && TokenPolicy.isUsable(expiresAt: stored.expiresAt)
        guard stored.refreshToken != nil else {
            stillUsable ? done(stored, nil, false)
                        : done(nil, L.t("session_expired_sign_in_again"), true)
            return
        }
        // Expired: serialize the refresh across app and extension.
        DispatchQueue.global(qos: .userInitiated).async {
            let lock = TokenRefreshLock.acquire(OpenAITokenStore.service)
            guard let current = OpenAITokenStore.load() ?? CodexAuthFile.load() else {
                TokenRefreshLock.release(lock)
                done(nil, L.t("session_expired_sign_in_again"), true)
                return
            }
            let currentRejected = rejectedToken == current.accessToken
            if !TokenPolicy.shouldRefresh(expiresAt: current.expiresAt, proactiveWindow: proactiveWindow,
                                          rejected: currentRejected) {
                TokenRefreshLock.release(lock)
                done(current, nil, false)
                return
            }
            let currentUsable = !currentRejected && TokenPolicy.isUsable(expiresAt: current.expiresAt)
            guard let rt = current.refreshToken else {
                TokenRefreshLock.release(lock)
                currentUsable ? done(current, nil, false)
                              : done(nil, L.t("session_expired_sign_in_again"), true)
                return
            }
            OpenAIOAuth.refresh(refreshToken: rt, accountID: current.accountID,
                                email: current.email) { creds, error in
                if let creds { OpenAITokenStore.save(creds) }
                TokenRefreshLock.release(lock)
                if let creds {
                    done(creds, nil, false)
                } else if currentUsable {
                    // Proactive renewal failed; the current token still works.
                    done(current, nil, false)
                } else if OAuthError.isAuthFailure(error) {
                    // Single refresher per token family: a rejection is real.
                    done(nil, L.t("session_expired_sign_in_again"), true)
                } else {
                    // Transient failure: keep the session, retry next cycle.
                    done(nil, error ?? L.t("no_session"), false)
                }
            }
        }
    }

    private struct UsageResult {
        var status: PlanStatus
        var rejected = false
    }

    private static func request(creds: OpenAIOAuth.Credentials,
                                completion: @escaping (UsageResult) -> Void) {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        if let id = creds.accountID {
            req.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            var result = UsageResult(status: PlanStatus(subscription: creds.planType))
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
                if http.statusCode == 401 || http.statusCode == 403 {
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
            if let rl = RateLimitParsing.findRateLimits(in: obj) {
                let parsed = RateLimitParsing.parseFull(rl)
                result.status.gauges = parsed.gauges
                result.status.subscription = parsed.planType
                    ?? (obj["plan_type"] as? String)
                    ?? creds.planType
                result.status.credits = parsed.credits
                result.status.spendLimit = parsed.spendLimit
                result.status.limitReachedReason = parsed.limitReachedReason
            }
            result.status.accountEmail = creds.email
            if result.status.gauges.isEmpty && !result.status.hasExtras {
                result.status.error = L.t("no_limit_data")
            }
        }.resume()
    }
}
