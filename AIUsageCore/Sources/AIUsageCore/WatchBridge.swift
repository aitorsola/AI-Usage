//
//  WatchBridge.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// The Apple Watch owns its OWN OAuth grant. The providers rotate refresh
// tokens on every refresh (single-use), so two devices sharing one token
// family can only race each other: whoever refreshed second was handed a
// rejection for a token the peer had just spent, and stale-token reuse can
// take the whole family down. The phone therefore authorizes a second time on
// the watch's behalf (watchOS cannot run the browser flow), parks the result
// under the watch service, hands it over ONCE through WatchConnectivity (an
// encrypted channel between paired devices) and forgets it as soon as the
// watch confirms receipt. From then on the watch refreshes on its own —
// app and complication, coordinated by the same cross-process lock.
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

    /// Providers carried by this payload.
    public var kinds: Set<ProviderKind> {
        var out: Set<ProviderKind> = []
        if anthropic != nil { out.insert(.anthropic) }
        if openAI != nil { out.insert(.openAI) }
        if deepSeekKey != nil { out.insert(.deepSeek) }
        return out
    }

    /// What the phone has parked for the watch and not yet delivered: the
    /// watch's own OAuth grants, plus the DeepSeek key (an API key does not
    /// rotate, so the phone simply shares its own).
    public static func pendingHandover(_ kinds: Set<ProviderKind>) -> WatchCredentials {
        WatchCredentials(
            anthropic: kinds.contains(.anthropic)
                ? AnthropicTokenStore.load(service: AnthropicTokenStore.watchService).map {
                    Anthropic(access: $0.accessToken, refresh: $0.refreshToken, expiresAt: $0.expiresAt)
                } : nil,
            openAI: kinds.contains(.openAI)
                ? OpenAITokenStore.load(service: OpenAITokenStore.watchService).map {
                    OpenAI(access: $0.accessToken, refresh: $0.refreshToken, expiresAt: $0.expiresAt,
                           accountID: $0.accountID, planType: $0.planType, email: $0.email)
                } : nil,
            deepSeekKey: kinds.contains(.deepSeek) ? DeepSeekKeyStore.load() : nil)
    }

    /// Phone side, after the watch acknowledged: the parked grant is the
    /// watch's now and must never be refreshed from here.
    public static func discardParked(_ kinds: Set<ProviderKind>) {
        if kinds.contains(.anthropic) { AnthropicTokenStore.delete(service: AnthropicTokenStore.watchService) }
        if kinds.contains(.openAI) { OpenAITokenStore.delete(service: OpenAITokenStore.watchService) }
    }

    /// Watch side: store what arrived as this device's session. Only the
    /// providers present are written — a handover of one provider never
    /// touches the others; removal is an explicit `signOut`.
    public func install() {
        if let a = anthropic {
            AnthropicTokenStore.save(AnthropicOAuth.OwnCredentials(
                accessToken: a.access, refreshToken: a.refresh, expiresAt: a.expiresAt))
        }
        if let o = openAI {
            OpenAITokenStore.save(OpenAIOAuth.Credentials(
                accessToken: o.access, refreshToken: o.refresh, expiresAt: o.expiresAt,
                accountID: o.accountID, planType: o.planType, email: o.email))
        }
        if let key = deepSeekKey {
            DeepSeekKeyStore.save(key)
        }
    }

    /// Watch side: drop the named providers' sessions.
    public static func signOut(_ kinds: Set<ProviderKind>) {
        if kinds.contains(.anthropic) { AnthropicTokenStore.delete() }
        if kinds.contains(.openAI) { OpenAITokenStore.delete() }
        if kinds.contains(.deepSeek) { DeepSeekKeyStore.delete() }
    }
}

/// The WatchConnectivity vocabulary shared by both apps. Everything travels as
/// user-info transfers (queued, delivered once, launching the receiving app in
/// the background if needed) except the display snapshot, which also rides
/// the persisted application context — it is not secret.
public enum WatchLink {
    /// Phone → watch: `WatchCredentials` (JSON) plus a `handover` id.
    public static let credentials = "credentials"
    public static let handover = "handover"
    /// Watch → phone: the `handover` id it installed, plus the `kinds` taken.
    public static let credentialsAck = "credentialsAck"
    public static let kinds = "kinds"
    /// Phone → watch: provider raw values to sign out of.
    public static let signOut = "signOut"
    /// Watch → phone: `[kind.rawValue: "ok" | "expired"]` for every provider
    /// the watch holds credentials for, sent after each refresh whose
    /// outcome changed.
    public static let watchStatus = "watchStatus"
    /// Phone → watch: the phone's rendered `WidgetSnapshot` (JSON).
    public static let snapshot = "snapshot"

    public static func encodeKinds(_ kinds: Set<ProviderKind>) -> [String] {
        kinds.map(\.rawValue).sorted()
    }

    public static func decodeKinds(_ raw: Any?) -> Set<ProviderKind> {
        Set((raw as? [String] ?? []).compactMap(ProviderKind.init(rawValue:)))
    }
}

/// What the watch reports about each session it holds.
public enum WatchSessionState: String, Codable {
    case ok, expired
}

// Builds the network-only widget snapshot shared by the iPhone app and the
// watch: one provider per configured account, in fixed order, honoring the
// remaining/used mode the host app dictates.
public enum SnapshotBuilder {
    // `credentialed` lists the providers with credentials stored on THIS
    // device. Passed in (instead of read from the store here) so callers
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

public extension WidgetSnapshot {
    /// The snapshot restricted to the named providers — what the watch keeps
    /// of a phone push, so a provider the watch holds no session for never
    /// flickers in and out between the phone's numbers and its own.
    func restricted(to kinds: Set<ProviderKind>) -> WidgetSnapshot {
        let names = Set(kinds.map(\.name))
        var copy = self
        copy.providers = providers.filter { names.contains($0.name) }
        return copy
    }
}
