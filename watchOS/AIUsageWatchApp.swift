//
//  AIUsageWatchApp.swift
//  AI Usage (watchOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI
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

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(store)
        }
    }
}

// Receives the ready-to-render snapshot from the iPhone and persists it in the
// watch's own App Group so the complication can read it. The watch renders
// exactly what the phone decided — providers, gauges and remaining/used mode.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: WidgetSnapshot?

    override init() {
        super.init()
        snapshot = WidgetShared.load()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

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
        guard let data = payload["snapshot"] as? Data,
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            self.snapshot = snap
            WidgetShared.save(snap)
            WidgetCenter.shared.reloadAllTimelines()
        }
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
