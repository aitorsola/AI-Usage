//
//  WatchSync.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import WatchConnectivity
import AIUsageCore

// Pushes the ready-to-render widget snapshot to the paired Apple Watch. The
// watch is a pure mirror: providers, gauges and the remaining/used mode all
// come decided from the phone — it never fetches or chooses anything itself.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    private var lastComplicationFingerprint: WidgetSnapshot?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let payload = ["snapshot": data]

        // Latest-state channel: delivered whenever the watch gets a chance.
        try? session.updateApplicationContext(payload)

        // Complication wake-ups are budgeted (~50/day): spend one only when
        // the rendered content actually changed.
        let fingerprint = snapshot.reloadFingerprint
        if session.isComplicationEnabled,
           fingerprint != lastComplicationFingerprint,
           session.remainingComplicationUserInfoTransfers > 0 {
            lastComplicationFingerprint = fingerprint
            session.transferCurrentComplicationUserInfo(payload)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
