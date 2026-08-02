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
        // The watch hands back credentials it rotated; refetch with them so a
        // session that had started failing recovers without a re-login.
        WatchSync.shared.onCredentialsMerged = { [weak self] in self?.refresh() }
        WatchSync.shared.activate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var providers: [ProviderData] { [anthropic, openAI, deepSeek] }

    // A fetch that never calls back must not pin `isRefreshing`: every later
    // tick of the 60 s timer would return instantly, so the snapshot would stop
    // moving and the watch would stop being pushed to — for the rest of the
    // process lifetime. Longer than the providers' own 15 s request timeouts
    // plus the token lock wait, so it only fires on a genuine hang.
    private static let refreshWatchdog: TimeInterval = 45
    // How long before a reload WidgetKit ignored is asked for again.
    private static let reloadRetryFloor: TimeInterval = 300

    private var refreshGeneration = 0

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshGeneration &+= 1
        let generation = refreshGeneration

        var settled = false
        func settle(_ apply: () -> Void) {
            guard !settled, generation == self.refreshGeneration else { return }
            settled = true
            self.isRefreshing = false
            apply()
        }

        let group = DispatchGroup()
        var claude = PlanStatus(), openAILive = PlanStatus(), ds = PlanStatus()
        var health: [ProviderKind: PlatformHealth] = [:]
        group.enter(); PlanFetcher.fetch { claude = $0; group.leave() }
        group.enter(); OpenAIUsageFetcher.fetch { openAILive = $0; group.leave() }
        group.enter(); DeepSeekFetcher.fetch { ds = $0; group.leave() }
        group.enter(); StatusFetcher.fetchAll([.anthropic, .openAI]) { health = $0; group.leave() }
        group.notify(queue: .main) {
            settle {
                self.anthropic = ProviderData(kind: .anthropic, plan: claude, available: !claude.needsLogin)
                self.openAI = ProviderData(kind: .openAI, plan: openAILive, available: !openAILive.needsLogin)
                self.deepSeek = ProviderData(kind: .deepSeek, plan: ds, available: !ds.needsLogin)
                self.health = health
                self.lastUpdated = Date()
                self.writeSnapshot()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshWatchdog) {
            // Drop the stuck attempt so the next timer tick can try again.
            settle {}
        }
    }

    private var lastReloadRequestedAt: Date?
    private var lastRequestedDigest: String?

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
        // Ask for a reload while what the widget actually drew disagrees with
        // what we have — not merely when the content changed since the last
        // reload we requested. WidgetKit drops requests once the daily budget
        // is spent, and treating a dropped one as delivered left the widget
        // showing stale numbers until they happened to move again.
        let wanted = snapshot.reloadDigest
        guard wanted != WidgetShared.renderedDigest() else { return }
        // Throttle only the REPEAT of a request WidgetKit dropped; content
        // that changed since the last request reloads immediately.
        if wanted == lastRequestedDigest, let last = lastReloadRequestedAt,
           Date().timeIntervalSince(last) < Self.reloadRetryFloor {
            return
        }
        lastRequestedDigest = wanted
        lastReloadRequestedAt = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
