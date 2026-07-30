//
//  WatchBridge.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Credentials handed from the iPhone to the watch over WatchConnectivity (an
// encrypted channel between paired devices). The watch cannot run the browser
// OAuth flows itself, so it receives the tokens once and from then on fetches
// plan limits on its own, storing them in its local Keychain.
public struct WatchCredentials: Codable {
    public struct Anthropic: Codable {
        public var access: String
        public var refresh: String?
        public var expiresAt: Date?
    }

    public struct OpenAI: Codable {
        public var access: String
        public var refresh: String?
        public var expiresAt: Date?
        public var accountID: String?
        public var planType: String?
        public var email: String?
    }

    public var anthropic: Anthropic?
    public var openAI: OpenAI?
    public var deepSeekKey: String?

    public init(anthropic: Anthropic? = nil, openAI: OpenAI? = nil, deepSeekKey: String? = nil) {
        self.anthropic = anthropic
        self.openAI = openAI
        self.deepSeekKey = deepSeekKey
    }

    public var isEmpty: Bool { anthropic == nil && openAI == nil && deepSeekKey == nil }

    // Identity of the long-lived secrets: changes on a login, a logout and a
    // rotated refresh token, but not on a plain access-token refresh. Only ever
    // compared within one process lifetime (String hashing is seeded per
    // launch), so it must not be persisted.
    public var identity: Int {
        "\(anthropic?.refresh ?? "")|\(openAI?.refresh ?? "")|\(deepSeekKey ?? "")".hashValue
    }

    // The credentials currently stored on this device (phone side).
    public static func current() -> WatchCredentials {
        WatchCredentials(
            anthropic: AnthropicTokenStore.load().map {
                Anthropic(access: $0.accessToken, refresh: $0.refreshToken, expiresAt: $0.expiresAt)
            },
            openAI: OpenAITokenStore.load().map {
                OpenAI(access: $0.accessToken, refresh: $0.refreshToken, expiresAt: $0.expiresAt,
                       accountID: $0.accountID, planType: $0.planType, email: $0.email)
            },
            deepSeekKey: DeepSeekKeyStore.load())
    }

    // Store into this device's Keychain (watch side), mirroring the phone:
    // signing out on the phone signs the watch out too.
    public func apply() {
        if let a = anthropic {
            AnthropicTokenStore.save(AnthropicOAuth.OwnCredentials(
                accessToken: a.access, refreshToken: a.refresh, expiresAt: a.expiresAt))
        } else {
            AnthropicTokenStore.delete()
        }
        if let o = openAI {
            OpenAITokenStore.save(OpenAIOAuth.Credentials(
                accessToken: o.access, refreshToken: o.refresh, expiresAt: o.expiresAt,
                accountID: o.accountID, planType: o.planType, email: o.email))
        } else {
            OpenAITokenStore.delete()
        }
        if let key = deepSeekKey {
            DeepSeekKeyStore.save(key)
        } else {
            DeepSeekKeyStore.delete()
        }
    }

    // Merge credentials received FROM the paired device. Unlike `apply()` this
    // is never destructive: the peer may hold fewer providers than we do, and
    // a missing one must not wipe a working session here.
    //
    // A provider is overwritten only when the incoming copy is strictly fresher
    // — which is exactly the case that matters: the peer refreshed, the shared
    // refresh token rotated, and our copy is now dead. Recovering from that is
    // what stops a rotation on one device from forcing a re-login on the other.
    @discardableResult
    public func merge() -> Bool {
        var changed = false
        if let a = anthropic, Self.isFresher(a.expiresAt, than: AnthropicTokenStore.load()?.expiresAt) {
            AnthropicTokenStore.save(AnthropicOAuth.OwnCredentials(
                accessToken: a.access, refreshToken: a.refresh, expiresAt: a.expiresAt))
            AuthFailureTracker.clear(AnthropicTokenStore.service)
            changed = true
        }
        if let o = openAI, Self.isFresher(o.expiresAt, than: OpenAITokenStore.load()?.expiresAt) {
            OpenAITokenStore.save(OpenAIOAuth.Credentials(
                accessToken: o.access, refreshToken: o.refresh, expiresAt: o.expiresAt,
                accountID: o.accountID, planType: o.planType, email: o.email))
            AuthFailureTracker.clear(OpenAITokenStore.service)
            changed = true
        }
        // A DeepSeek API key does not rotate, so it is only ever filled in.
        if let key = deepSeekKey, DeepSeekKeyStore.load() == nil {
            DeepSeekKeyStore.save(key)
            changed = true
        }
        return changed
    }

    static func isFresher(_ incoming: Date?, than stored: Date?) -> Bool {
        guard let incoming else { return false }
        guard let stored else { return true }
        return incoming > stored
    }
}

// Builds the network-only widget snapshot shared by the iPhone app and the
// watch: one provider per configured account, in fixed order, honoring the
// remaining/used mode the host app dictates.
public enum SnapshotBuilder {
    // `credentialed` lists the providers with credentials stored on THIS
    // device. Passed in (instead of read from the Keychain here) so callers
    // decide and tests stay deterministic.
    public static func network(anthropic: PlanStatus, openAI: PlanStatus, deepSeek: PlanStatus,
                               credentialed: Set<ProviderKind> = [],
                               health: [ProviderKind: PlatformHealth] = [:],
                               showRemaining: Bool, updated: Date = Date()) -> WidgetSnapshot {
        var providers: [WSProvider] = []
        let all: [(ProviderKind, PlanStatus)] = [(.anthropic, anthropic), (.openAI, openAI), (.deepSeek, deepSeek)]
        for (kind, plan) in all {
            // Never-signed-in providers stay out of the widget; a provider
            // WITH credentials always shows up — with a note when its session
            // or fetch went wrong, instead of silently vanishing.
            guard !plan.needsLogin || credentialed.contains(kind) else { continue }
            let data = ProviderData(kind: kind, plan: plan, available: true)
            let gauges = data.menuGauges.map {
                WSGauge(label: $0.label,
                        used: min(max($0.utilization, 0), 100),
                        reset: $0.resetsAt.map(Formatters.resetCompact))
            }
            var lines: [String] = []
            if kind == .deepSeek, let balance = plan.credits?.balance {
                lines.append("\(L.t("balance")) \(Formatters.money(balance) ?? balance)")
            }
            var note: String?
            if plan.needsLogin {
                note = plan.error ?? L.t("not_signed_in")
            } else if gauges.isEmpty, !plan.hasExtras, let error = plan.error {
                note = error
            }
            providers.append(WSProvider(name: kind.name, colorHex: kind.colorHex,
                                        subscription: plan.subscription, gauges: gauges,
                                        lines: lines, limitReached: plan.limitReachedReason,
                                        note: note, health: health[kind]))
        }
        return WidgetSnapshot(providers: providers, showRemaining: showRemaining,
                              weekTitle: "", weekBars: [],
                              updatedText: Formatters.time(updated), date: updated)
    }
}
