//
//  WidgetRefresh.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Lets a widget/complication extension refresh WITHOUT the host app: it reuses
// the app-written snapshot when it is fresh, and otherwise fetches the provider
// endpoints itself (Weather-widget style). The extension reaches the tokens
// through the keychain access group it shares with the app. Requires the
// iOS/watchOS keychain-sharing entitlement; on macOS the always-running menu
// bar app drives the widget instead, so this is not used there.
public enum WidgetRefresh {
    // Providers whose credentials are readable on THIS device.
    public static func credentialedProviders() -> Set<ProviderKind> {
        var out: Set<ProviderKind> = []
        if AnthropicTokenStore.load() != nil { out.insert(.anthropic) }
        if OpenAITokenStore.load() != nil { out.insert(.openAI) }
        if DeepSeekKeyStore.load() != nil { out.insert(.deepSeek) }
        return out
    }

    /// Produces a snapshot for an extension's timeline.
    /// - reuses the app's snapshot if younger than `maxAge`;
    /// - else fetches the endpoints directly and persists the result;
    /// - on `timeout` (or no credentials) falls back to the last snapshot so a
    ///   slow network never blanks the widget.
    public static func snapshot(maxAge: TimeInterval = 300, timeout: TimeInterval = 15,
                                completion: @escaping (WidgetSnapshot) -> Void) {
        let existing = WidgetShared.load()
        if let existing, existing.age < maxAge {
            completion(existing)
            return
        }

        let credentialed = credentialedProviders()
        guard !credentialed.isEmpty else {
            completion(existing ?? .placeholder)
            return
        }
        let showRemaining = existing?.showRemaining ?? true

        var claude = PlanStatus(needsLogin: true)
        var openAI = PlanStatus(needsLogin: true)
        var deepSeek = PlanStatus(needsLogin: true)
        let group = DispatchGroup()
        if credentialed.contains(.anthropic) {
            group.enter(); PlanFetcher.fetch { claude = $0; group.leave() }
        }
        if credentialed.contains(.openAI) {
            group.enter(); OpenAIUsageFetcher.fetch { openAI = $0; group.leave() }
        }
        if credentialed.contains(.deepSeek) {
            group.enter(); DeepSeekFetcher.fetch { deepSeek = $0; group.leave() }
        }

        var finished = false
        func complete(_ snapshot: WidgetSnapshot, persist: Bool) {
            guard !finished else { return }
            finished = true
            if persist { WidgetShared.save(snapshot) }
            completion(snapshot)
        }
        group.notify(queue: .main) {
            complete(SnapshotBuilder.network(anthropic: claude, openAI: openAI, deepSeek: deepSeek,
                                             credentialed: credentialed, showRemaining: showRemaining),
                     persist: true)
        }
        // Never hold the extension past its budget: keep last known good data.
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            complete(existing ?? .placeholder, persist: false)
        }
    }
}
