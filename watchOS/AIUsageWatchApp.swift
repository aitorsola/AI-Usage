//
//  AIUsageWatchApp.swift
//  AI Usage (watchOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI
import WatchKit
import WatchConnectivity
import WidgetKit
import AIUsageCore

extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

@main
struct AIUsageWatchApp: App {
    @StateObject private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
            if phase == .background { WatchStore.scheduleBackgroundRefresh() }
        }
        // Periodic background fetch so the complication stays fresh without
        // the phone. The next slot is booked BEFORE fetching: if the network
        // hangs or the runtime suspends us mid-await, the chain survives.
        .backgroundTask(.appRefresh("refresh")) {
            WatchStore.scheduleBackgroundRefresh()
            await store.backgroundRefresh()
        }
    }
}

// The watch fetches plan limits on its own with OAuth grants of its OWN,
// obtained by the iPhone on its behalf and handed over once (watchOS cannot
// run the browser flows). Nobody else refreshes them, so a rotated refresh
// token can never be spent twice. Phone snapshot pushes still land instantly
// when both apps are alive; between pushes the watch refreshes independently —
// on foreground and via background app refresh — and reports the state of
// each session back so the phone can offer to reconnect a dead one.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: WidgetSnapshot?

    private var refreshing = false
    private var refreshGeneration = 0
    private var lastReloadRequestedAt: Date?
    private var lastRequestedDigest: String?
    private var lastReportedStatus: [String: String]?

    // A fetch that never calls back must not pin `refreshing` forever: that is
    // exactly what a blocked cross-process token lock did, and from then on
    // every foreground open and every background refresh returned instantly.
    // Longer than the providers' own 15 s request timeouts plus the token lock
    // wait, so it only ever fires on a genuine hang.
    private static let refreshWatchdog: TimeInterval = 45
    // How long before a reload WidgetKit ignored is asked for again.
    private static let reloadRetryFloor: TimeInterval = 300
    // Renew tokens this far ahead from the app (foreground and background
    // refresh), so the complication — which only refreshes what already
    // expired — almost never has to hold the refresh lock itself.
    private static let proactiveRefresh: TimeInterval = 2 * 3600

    // Builds before 22 gave the watch a COPY of the iPhone's session, and both
    // devices refreshed it. That copy must go the first time this build runs:
    // left in place it would keep spending the phone's (single-use) refresh
    // tokens. The DeepSeek key is not a session and stays.
    private static let ownGrantMigrationKey = "migratedToOwnGrant"

    override init() {
        super.init()
        if !UserDefaults.standard.bool(forKey: Self.ownGrantMigrationKey) {
            WatchCredentials.signOut([.anthropic, .openAI])
            UserDefaults.standard.set(true, forKey: Self.ownGrantMigrationKey)
        }
        snapshot = WidgetShared.load()
        // Every launch re-books the chain — including background launches
        // (a complication push waking the app) and the first run after a
        // reboot, which clears previously scheduled refreshes.
        Self.scheduleBackgroundRefresh()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Independent fetch

    var hasCredentials: Bool { !Self.credentialed().isEmpty }

    private static func credentialed() -> Set<ProviderKind> {
        var out: Set<ProviderKind> = []
        if AnthropicTokenStore.load() != nil { out.insert(.anthropic) }
        if OpenAITokenStore.load() != nil { out.insert(.openAI) }
        if DeepSeekKeyStore.load() != nil { out.insert(.deepSeek) }
        return out
    }

    func refresh(completion: (() -> Void)? = nil) {
        guard !refreshing, hasCredentials else { completion?(); return }
        refreshing = true
        refreshGeneration &+= 1
        let generation = refreshGeneration

        // Both arms below run on the main queue, so this settles without a lock.
        var settled = false
        func settle(_ apply: () -> Void) {
            guard !settled, generation == self.refreshGeneration else { return }
            settled = true
            self.refreshing = false
            apply()
            completion?()
        }

        let group = DispatchGroup()
        var claude = PlanStatus(needsLogin: true)
        var openAI = PlanStatus(needsLogin: true)
        var deepSeek = PlanStatus(needsLogin: true)
        let held = Self.credentialed()
        if held.contains(.anthropic) {
            group.enter(); PlanFetcher.fetch(proactiveWindow: Self.proactiveRefresh) { claude = $0; group.leave() }
        }
        if held.contains(.openAI) {
            group.enter(); OpenAIUsageFetcher.fetch(proactiveWindow: Self.proactiveRefresh) { openAI = $0; group.leave() }
        }
        if held.contains(.deepSeek) {
            group.enter(); DeepSeekFetcher.fetch { deepSeek = $0; group.leave() }
        }
        group.notify(queue: .main) {
            settle {
                let showRemaining = (UserDefaults.standard.string(forKey: SettingsKeys.limitDisplay)
                    ?? LimitDisplay.remaining.rawValue) != LimitDisplay.used.rawValue
                let credentialed = Self.credentialed()
                self.show(SnapshotBuilder.network(anthropic: claude, openAI: openAI,
                                                  deepSeek: deepSeek, credentialed: credentialed,
                                                  showRemaining: showRemaining))
                self.reportStatus([.anthropic: claude, .openAI: openAI, .deepSeek: deepSeek],
                                  credentialed: credentialed)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshWatchdog) {
            // Drop the stuck attempt and let the next cycle try again, rather
            // than leaving the store unable to refresh for good.
            settle {}
        }
    }

    func backgroundRefresh() async {
        // The background runtime window is short: cap the fetch so this task
        // always returns instead of hanging until the runtime kills it. Both
        // completion paths land on the main queue, so the flag is race-free.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { [weak self] in
                var resumed = false
                func finishOnce() {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                guard let self else { finishOnce(); return }
                self.refresh { finishOnce() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { finishOnce() }
            }
        }
    }

    // Tell the phone how each session held here is doing, whenever that
    // changes: it is the only way the phone learns that a watch grant died
    // (its refresh token was rejected) and can offer to hand over a new one.
    private func reportStatus(_ plans: [ProviderKind: PlanStatus], credentialed: Set<ProviderKind>) {
        var status: [String: String] = [:]
        for kind in credentialed {
            let dead = plans[kind]?.needsLogin ?? false
            status[kind.rawValue] = (dead ? WatchSessionState.expired : .ok).rawValue
        }
        guard status != lastReportedStatus else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        lastReportedStatus = status
        WCSession.default.transferUserInfo([WatchLink.watchStatus: status])
    }

    static func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(30 * 60),
            userInfo: "refresh" as NSString) { _ in }
    }

    // MARK: - Phone pushes (credentials + freshest snapshot)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        let context = session.receivedApplicationContext
        DispatchQueue.main.async { self.apply(context) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.apply(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { self.apply(userInfo) }
    }

    // Always on the main queue: it touches the store's state and the
    // credential store together.
    private func apply(_ payload: [String: Any]) {
        // A handover: install the grant(s) as this device's own sessions and
        // acknowledge, so the phone drops its parked copy and never refreshes
        // it. Then fetch right away — the rings should not wait 30 minutes.
        if let credData = payload[WatchLink.credentials] as? Data,
           let creds = try? JSONDecoder().decode(WatchCredentials.self, from: credData),
           !creds.isEmpty {
            creds.install()
            lastReportedStatus = nil
            if WCSession.default.activationState == .activated {
                WCSession.default.transferUserInfo([
                    WatchLink.credentialsAck: (payload[WatchLink.handover] as? String) ?? "",
                    WatchLink.kinds: WatchLink.encodeKinds(creds.kinds),
                ])
            }
            refresh()
        }
        let signOut = WatchLink.decodeKinds(payload[WatchLink.signOut])
        if !signOut.isEmpty {
            WatchCredentials.signOut(signOut)
            lastReportedStatus = nil
            if hasCredentials {
                refresh()
            } else {
                snapshot = nil
                WidgetShared.save(WidgetSnapshot(providers: [], showRemaining: true, weekTitle: "",
                                                 weekBars: [], updatedText: "", date: Date()))
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        // The phone's rendered snapshot is a bonus while both apps are alive.
        // Keep only the providers this watch holds a session for, so a
        // provider the phone has and the watch does not never flickers in
        // and out between the phone's numbers and the watch's own fetches.
        guard let data = payload[WatchLink.snapshot] as? Data,
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        let held = Self.credentialed()
        guard !held.isEmpty else { return }
        show(snap.restricted(to: held))
    }

    private func show(_ snap: WidgetSnapshot) {
        snapshot = snap
        // Persist the host-dictated display mode for independent refreshes.
        UserDefaults.standard.set(snap.showRemaining ? LimitDisplay.remaining.rawValue
                                                     : LimitDisplay.used.rawValue,
                                  forKey: SettingsKeys.limitDisplay)
        WidgetShared.save(snap)
        requestReloadIfStale(snap)
    }

    // Reloads are budgeted (~40-70/day) and this runs on every phone push AND
    // every self-refresh, so one per call exhausted the budget. But gating on
    // "did the content change since the last reload we ASKED for" was worse in
    // its own way: WidgetKit drops requests once the budget is spent, and the
    // dropped one was recorded as delivered — so the change was never asked for
    // again and the complication kept a stale render even with the app open.
    //
    // Compare against what the complication actually drew (it records that from
    // getTimeline) and keep asking, slowly, until the two agree.
    private func requestReloadIfStale(_ snap: WidgetSnapshot) {
        let wanted = snap.reloadDigest
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

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            Group {
                if let snap = store.snapshot, !snap.providers.isEmpty {
                    List {
                        ForEach(snap.providers, id: \.name) { provider in
                            ProviderCell(provider: provider, showRemaining: snap.showRemaining)
                        }
                        ComplicationStatusCell(appSnapshot: snap)
                    }
                    .listStyle(.carousel)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "asterisk")
                            .font(.title3)
                            .foregroundStyle(Color(hex: "#D97757"))
                        Text(L.t("connect_from_iphone"))
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI Usage")
        }
    }
}

// Whether the complication is actually being run by WidgetKit, and what it drew
// the last time it was. Everything else about a stuck complication is invisible
// from here: the app can request reloads all day and never learn that WidgetKit
// dropped every one of them, or that the extension is drawing the placeholder
// because it cannot reach the shared container.
private struct ComplicationStatusCell: View {
    let appSnapshot: WidgetSnapshot

    var body: some View {
        let render = WidgetShared.lastRender()
        let pings = WidgetShared.pings()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "circle.dotted.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(L.t("complication")).font(.headline)
            }
            // One row per WidgetKit entry point. The pattern is the diagnosis:
            // all "—"        → chronod never launches the extension (registro).
            // gallery only   → it runs, but no face slot asks for a timeline.
            // timeline stale → reload requests are being dropped (budget).
            row(L.t("phase_gallery"), pingText(pings[.placeholder], pings[.snapshot]))
            row(L.t("phase_timeline"), pingText(pings[.timeline]))
            if let render {
                row(L.t("last_drawn"), Self.elapsed(render.age))
                row(L.t("source"), Self.sourceLabel(render.source))
                row(L.t("providers"), "\(render.providerCount)")
                let inSync = render.digest == appSnapshot.reloadDigest
                Text(inSync ? L.t("complication_in_sync") : L.t("complication_behind"))
                    .font(.caption2)
                    .foregroundStyle(inSync ? Color(hex: "#34C759") : Color(hex: "#FF9500"))
                    .lineLimit(2)
            } else {
                // No render record: getTimeline has never completed since this
                // build was installed. Combined with the phase rows above this
                // pinpoints where the pipeline dies.
                Text(L.t("complication_never_ran"))
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "#FF3B30"))
            }
        }
        .padding(.vertical, 4)
    }

    // "12 × hace 3 min", or "—" if the phase never ran. When two phases feed
    // one row (the gallery pair) the freshest one wins.
    private func pingText(_ candidates: WidgetPing?...) -> String {
        let best = candidates.compactMap { $0 }.min { $0.age < $1.age }
        guard let best else { return "—" }
        return "\(best.count) × \(Self.elapsed(best.age))"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(value).font(.caption2.monospacedDigit()).lineLimit(1)
        }
    }

    private static func elapsed(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return L.t("just_now") }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours) h" : "\(hours / 24) d"
    }

    private static func sourceLabel(_ source: WidgetRenderSource) -> String {
        switch source {
        case .appSnapshot: return L.t("source_app")
        case .selfFetched: return L.t("source_network")
        case .fallback: return L.t("source_fallback")
        case .placeholder: return L.t("source_placeholder")
        }
    }
}

private struct ProviderCell: View {
    let provider: WSProvider
    let showRemaining: Bool

    var body: some View {
        let color = Color(hex: provider.colorHex)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(provider.name).font(.headline)
                if let sub = provider.subscription {
                    Text(sub.capitalized).font(.footnote).foregroundStyle(.secondary)
                }
                if let health = provider.health {
                    Spacer()
                    Image(systemName: health.iconName)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: health.colorHex))
                }
            }
            if let health = provider.health, health.isNoteworthy {
                Text(health.label).font(.caption2).foregroundStyle(Color(hex: health.colorHex)).lineLimit(1)
            }
            if let reason = provider.limitReached {
                Text(reason).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
            if let note = provider.note {
                Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
            ForEach(Array(provider.gauges.prefix(2).enumerated()), id: \.offset) { _, gauge in
                gaugeRow(gauge, color: color)
            }
            ForEach(provider.lines, id: \.self) { line in
                Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func gaugeRow(_ gauge: WSGauge, color: Color) -> some View {
        let used = min(max(gauge.used, 0), 100)
        let shown = showRemaining ? 100 - used : used
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(gauge.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(Int(shown.rounded()))%").font(.caption.monospacedDigit().bold())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.2))
                    Capsule().fill(color).frame(width: max(3, geo.size.width * shown / 100))
                }
            }
            .frame(height: 5)
            if let reset = gauge.reset {
                Text(reset).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}
