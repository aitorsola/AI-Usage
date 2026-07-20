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
    private var lastCredentialIdentity: Int?

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

        // Snapshot only in the persisted application context — it is not secret.
        try? session.updateApplicationContext(["snapshot": data])

        // Credentials go via transferUserInfo (queued, delivered once, then
        // removed) so tokens don't linger at rest in the persisted context —
        // and only when the long-lived secrets change (a login/logout or a
        // rotated refresh token), not on every access-token refresh.
        let creds = WatchCredentials.current()
        let identity = "\(creds.anthropic?.refresh ?? "")|\(creds.openAI?.refresh ?? "")|\(creds.deepSeekKey ?? "")".hashValue
        if identity != lastCredentialIdentity, let credData = try? JSONEncoder().encode(creds) {
            lastCredentialIdentity = identity
            session.transferUserInfo(["credentials": credData])
        }

        // Complication wake-ups are budgeted (~50/day): spend one only when the
        // rendered content changed. Snapshot only — no credentials.
        let fingerprint = snapshot.reloadFingerprint
        if session.isComplicationEnabled,
           fingerprint != lastComplicationFingerprint,
           session.remainingComplicationUserInfoTransfers > 0 {
            lastComplicationFingerprint = fingerprint
            session.transferCurrentComplicationUserInfo(["snapshot": data])
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
