//
//  UsageStoreiOS.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import AIUsageCore
import Combine
import WidgetKit

// Network-only counterpart of the macOS UsageStore. iOS has no local CLI logs,
// so this fetches plan limits (Claude, OpenAI) and balance (DeepSeek) straight
// from the provider endpoints and writes the shared widget snapshot.
@MainActor
final class UsageStoreiOS: ObservableObject {
    @Published var anthropic = ProviderData(kind: .anthropic)
    @Published var openAI = ProviderData(kind: .openAI)
    @Published var deepSeek = ProviderData(kind: .deepSeek)
    @Published var isRefreshing = false
    @Published var lastUpdated = Date()
    @Published var health: [ProviderKind: PlatformHealth] = [:]

    lazy var anthropicLogin = ProviderLogin(.anthropic) { [weak self] in self?.refresh() }
    lazy var openAILogin = ProviderLogin(.openAI) { [weak self] in self?.refresh() }

    private var timer: Timer?

    init() {
        WatchSync.shared.activate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var providers: [ProviderData] { [anthropic, openAI, deepSeek] }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let group = DispatchGroup()
        var claude = PlanStatus(), openAILive = PlanStatus(), ds = PlanStatus()
        var health: [ProviderKind: PlatformHealth] = [:]
        group.enter(); PlanFetcher.fetch { claude = $0; group.leave() }
        group.enter(); OpenAIUsageFetcher.fetch { openAILive = $0; group.leave() }
        group.enter(); DeepSeekFetcher.fetch { ds = $0; group.leave() }
        group.enter(); StatusFetcher.fetchAll([.anthropic, .openAI]) { health = $0; group.leave() }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.anthropic = ProviderData(kind: .anthropic, plan: claude, available: !claude.needsLogin)
            self.openAI = ProviderData(kind: .openAI, plan: openAILive, available: !openAILive.needsLogin)
            self.deepSeek = ProviderData(kind: .deepSeek, plan: ds, available: !ds.needsLogin)
            self.health = health
            self.lastUpdated = Date()
            self.isRefreshing = false
            self.writeSnapshot()
        }
    }

    private var lastReloadFingerprint: WidgetSnapshot?
    private var lastReloadAt: Date?

    func writeSnapshot() {
        let showRemaining = (UserDefaults.standard.string(forKey: SettingsKeys.limitDisplay)
            ?? LimitDisplay.remaining.rawValue) != LimitDisplay.used.rawValue
        var credentialed: Set<ProviderKind> = []
        if AnthropicTokenStore.load() != nil { credentialed.insert(.anthropic) }
        if OpenAITokenStore.load() != nil || CodexAuthFile.load() != nil { credentialed.insert(.openAI) }
        if DeepSeekKeyStore.load() != nil { credentialed.insert(.deepSeek) }
        let snapshot = SnapshotBuilder.network(anthropic: anthropic.plan, openAI: openAI.plan,
                                               deepSeek: deepSeek.plan, credentialed: credentialed,
                                               health: health,
                                               showRemaining: showRemaining, updated: lastUpdated)
        WidgetShared.save(snapshot)
        WatchSync.shared.push(snapshot)
        // Reload on any real content change, and at least every few minutes
        // while the app is foregrounded so the reset countdown never freezes.
        let fingerprint = snapshot.reloadFingerprint
        let now = Date()
        let overdue = lastReloadAt.map { now.timeIntervalSince($0) >= 300 } ?? true
        if fingerprint != lastReloadFingerprint || overdue {
            lastReloadFingerprint = fingerprint
            lastReloadAt = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
