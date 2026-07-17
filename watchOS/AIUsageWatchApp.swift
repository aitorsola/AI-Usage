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
        // the phone: refresh and schedule the next slot.
        .backgroundTask(.appRefresh("refresh")) {
            await store.backgroundRefresh()
            WatchStore.scheduleBackgroundRefresh()
        }
    }
}

// The watch fetches plan limits on its own using credentials handed over once
// by the iPhone (it cannot run the browser OAuth flows itself). Phone pushes
// still land instantly when both apps are alive; between pushes the watch
// refreshes independently — on foreground and via background app refresh.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: WidgetSnapshot?

    private var refreshing = false

    override init() {
        super.init()
        snapshot = WidgetShared.load()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Independent fetch

    var hasCredentials: Bool {
        AnthropicTokenStore.load() != nil || OpenAITokenStore.load() != nil
            || DeepSeekKeyStore.load() != nil
    }

    func refresh(completion: (() -> Void)? = nil) {
        guard !refreshing, hasCredentials else { completion?(); return }
        refreshing = true

        let group = DispatchGroup()
        var claude = PlanStatus(needsLogin: true)
        var openAI = PlanStatus(needsLogin: true)
        var deepSeek = PlanStatus(needsLogin: true)
        if AnthropicTokenStore.load() != nil {
            group.enter(); PlanFetcher.fetch { claude = $0; group.leave() }
        }
        if OpenAITokenStore.load() != nil {
            group.enter(); OpenAIUsageFetcher.fetch { openAI = $0; group.leave() }
        }
        if DeepSeekKeyStore.load() != nil {
            group.enter(); DeepSeekFetcher.fetch { deepSeek = $0; group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { completion?(); return }
            self.refreshing = false
            let showRemaining = (UserDefaults.standard.string(forKey: SettingsKeys.limitDisplay)
                ?? LimitDisplay.remaining.rawValue) != LimitDisplay.used.rawValue
            self.show(SnapshotBuilder.network(anthropic: claude, openAI: openAI,
                                              deepSeek: deepSeek, showRemaining: showRemaining))
            completion?()
        }
    }

    func backgroundRefresh() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refresh { continuation.resume() }
        }
    }

    static func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(30 * 60),
            userInfo: "refresh" as NSString) { _ in }
    }

    // MARK: - Phone pushes (credentials + freshest snapshot)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(userInfo)
    }

    private func apply(_ payload: [String: Any]) {
        if let credData = payload["credentials"] as? Data,
           let creds = try? JSONDecoder().decode(WatchCredentials.self, from: credData) {
            creds.apply()
        }
        guard let data = payload["snapshot"] as? Data,
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        DispatchQueue.main.async { self.show(snap) }
    }

    private func show(_ snap: WidgetSnapshot) {
        snapshot = snap
        // Persist the host-dictated display mode for independent refreshes.
        UserDefaults.standard.set(snap.showRemaining ? LimitDisplay.remaining.rawValue
                                                     : LimitDisplay.used.rawValue,
                                  forKey: SettingsKeys.limitDisplay)
        WidgetShared.save(snap)
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
                    }
                    .listStyle(.carousel)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "asterisk")
                            .font(.title3)
                            .foregroundStyle(Color(hex: "#D97757"))
                        Text(L.t("open_iphone_app"))
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
            }
            if let reason = provider.limitReached {
                Text(reason).font(.caption2).foregroundStyle(.red).lineLimit(2)
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
