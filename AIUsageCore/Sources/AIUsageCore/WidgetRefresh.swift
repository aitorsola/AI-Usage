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
// through CredentialStore — the shared keychain access group on iOS/watchOS,
// the App Group container on macOS — and refreshes them under the same
// cross-process lock as the app, never proactively (proactiveWindow 0): the
// app renews hours ahead, so the extension only ever refreshes what already
// expired while the app was closed.
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
    /// The completion also reports WHERE the content came from, so the
    /// extension can record it: when a complication refuses to move, "it never
    /// ran" and "it ran and drew the placeholder" look identical from outside.
    ///
    /// `timeout` MUST stay well under WidgetKit's own budget for producing a
    /// timeline. It used to be 15 s, which is around that budget: on the watch,
    /// where the providers are reached over the phone's link, the fetch
    /// regularly outlived it, so WidgetKit killed the extension BEFORE the
    /// fallback fired. An extension that returns no timeline renders nothing at
    /// all — which is the blank complication, and also the blank preview in the
    /// picker, since chronod has no successful render to show there either.
    public static func snapshot(maxAge: TimeInterval = 300, timeout: TimeInterval = 5,
                                completion: @escaping (WidgetSnapshot, WidgetRenderSource) -> Void) {
        let existing = WidgetShared.load()
        if let existing, existing.age < maxAge {
            completion(existing, .appSnapshot)
            return
        }

        let credentialed = credentialedProviders()
        guard !credentialed.isEmpty else {
            // No session on this device: say so. Falling back to the last
            // snapshot here froze the watch complication on old numbers after
            // its session was removed.
            completion(.empty(), .placeholder)
            return
        }
        let showRemaining = existing?.showRemaining ?? true

        var claude = PlanStatus(needsLogin: true)
        var openAI = PlanStatus(needsLogin: true)
        var deepSeek = PlanStatus(needsLogin: true)
        var health: [ProviderKind: PlatformHealth] = [:]
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
        group.enter(); StatusFetcher.fetchAll([.anthropic, .openAI]) { health = $0; group.leave() }

        // Two queues race to deliver now, so the guard needs a real lock.
        let lock = NSLock()
        var delivered = false
        func deliver(_ snapshot: WidgetSnapshot, _ source: WidgetRenderSource) {
            lock.lock()
            let first = !delivered
            delivered = true
            lock.unlock()
            guard first else { return }
            completion(snapshot, source)
        }

        // Neither arm runs on the main queue any more: the fallback is what
        // keeps WidgetKit from killing the extension empty-handed, so it must
        // not be sitting behind whatever else the main queue is doing.
        group.notify(queue: .global(qos: .userInitiated)) {
            let fresh = SnapshotBuilder.network(anthropic: claude, openAI: openAI, deepSeek: deepSeek,
                                                credentialed: credentialed, health: health,
                                                showRemaining: showRemaining)
            // Persist even when the fallback already answered: the fetch that
            // arrived too late for THIS timeline is exactly what makes the next
            // one fresh. Discarding it left the extension re-fetching from
            // scratch every time and never getting ahead.
            WidgetShared.save(fresh)
            deliver(fresh, .selfFetched)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
            deliver(existing ?? .placeholder, existing == nil ? .placeholder : .fallback)
        }
    }
}
