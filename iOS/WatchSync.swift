//
//  WatchSync.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import WatchConnectivity
import AIUsageCore

// Pushes the ready-to-render widget snapshot to the paired Apple Watch, which
// renders it as the phone decided (providers, gauges, remaining/used mode).
//
// The watch also fetches on its own so the complication stays fresh with the
// phone away, which means BOTH devices refresh the same OAuth token family —
// and the provider rotates the refresh token on every refresh. So credentials
// travel in both directions: whoever rotated last hands its copy to the other,
// which merges it instead of treating its own dead copy as a lost session.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// Called after credentials from the watch replaced fresher ones here, so
    /// the store can retry a fetch that had been failing.
    var onCredentialsMerged: (() -> Void)?

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
        let identity = creds.identity
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

    // Credentials coming back from the watch: it refreshed on its own and the
    // refresh token rotated, so our copy is dead. Merging is non-destructive —
    // only strictly fresher providers are taken, and nothing is ever deleted.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["credentials"] as? Data,
              let creds = try? JSONDecoder().decode(WatchCredentials.self, from: data),
              creds.merge() else { return }
        // Don't hand straight back what we just took.
        lastCredentialIdentity = WatchCredentials.current().identity
        DispatchQueue.main.async { [weak self] in self?.onCredentialsMerged?() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
