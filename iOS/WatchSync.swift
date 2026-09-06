//
//  WatchSync.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import Combine
import WatchConnectivity
import AIUsageCore

/// The phone's view of each session on the watch.
enum WatchLinkState: String {
    case none        // never handed over (or disconnected)
    case pending     // parked here and queued; the watch has not confirmed yet
    case connected   // the watch holds it and refreshes it on its own
    case expired     // the watch reported its refresh token was rejected
}

// The iPhone side of the watch link.
//
// The watch owns its own OAuth grants (see WatchBridge): the phone obtains one
// on its behalf, parks it, queues it as a user-info transfer — delivered once,
// launching the watch app in the background if needed — and drops its copy
// the moment the watch acknowledges. Credentials never travel back: nothing
// here refreshes them, so the two devices can no longer invalidate each
// other's session.
//
// The display snapshot still rides along on every phone refresh (application
// context + a budgeted complication push when the rendered content changed);
// the watch treats it as a bonus and keeps fetching on its own.
final class WatchSync: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSync()

    @Published private(set) var link: [ProviderKind: WatchLinkState] = [:]
    @Published private(set) var isWatchAvailable = false

    private var lastComplicationFingerprint: WidgetSnapshot?
    private static let handoverKinds: [ProviderKind] = [.anthropic, .openAI, .deepSeek]

    override init() {
        super.init()
        for kind in Self.handoverKinds {
            link[kind] = WatchLinkState(rawValue: UserDefaults.standard.string(forKey: Self.key(kind)) ?? "") ?? .none
        }
    }

    /// Must run at launch — including background launches WatchConnectivity
    /// performs to deliver the watch's acknowledgements — so it lives in the
    /// app delegate rather than a view's state object.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Handover

    /// Queues the parked session for `kind` (obtained through the watch login
    /// flow, or the DeepSeek key the phone already has) to the watch.
    func handOver(_ kind: ProviderKind) {
        dispatchPrecondition(condition: .onQueue(.main))
        let creds = WatchCredentials.pendingHandover([kind])
        guard !creds.isEmpty, let data = try? JSONEncoder().encode(creds) else { return }
        set(kind, .pending)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [WatchLink.credentials: data,
                                      WatchLink.handover: UUID().uuidString]
        WCSession.default.transferUserInfo(payload)
    }

    /// Signs the watch out of `kind` and forgets anything parked for it.
    func disconnect(_ kind: ProviderKind) {
        dispatchPrecondition(condition: .onQueue(.main))
        WatchCredentials.discardParked([kind])
        set(kind, .none)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([WatchLink.signOut: WatchLink.encodeKinds([kind])])
    }

    // `link` is only touched on the main queue; delegate callbacks hop there.
    private func set(_ kind: ProviderKind, _ state: WatchLinkState) {
        link[kind] = state
        UserDefaults.standard.set(state.rawValue, forKey: Self.key(kind))
    }

    private static func key(_ kind: ProviderKind) -> String { "watchLink.\(kind.rawValue)" }

    /// A handover marked pending whose transfer is no longer queued (the app
    /// was killed before WatchConnectivity persisted it) is queued again.
    private func requeueOrphanedHandovers() {
        let session = WCSession.default
        let queued = session.outstandingUserInfoTransfers.contains {
            $0.userInfo[WatchLink.credentials] != nil
        }
        guard !queued else { return }
        for kind in Self.handoverKinds where link[kind] == .pending {
            handOver(kind)
        }
    }

    // MARK: - Snapshot

    func push(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }

        // Snapshot only in the persisted application context — it is not secret.
        try? session.updateApplicationContext([WatchLink.snapshot: data])

        // Complication wake-ups are budgeted (~50/day): spend one only when the
        // rendered content changed.
        let fingerprint = snapshot.reloadFingerprint
        if session.isComplicationEnabled,
           fingerprint != lastComplicationFingerprint,
           session.remainingComplicationUserInfoTransfers > 0 {
            lastComplicationFingerprint = fingerprint
            session.transferCurrentComplicationUserInfo([WatchLink.snapshot: data])
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        refreshAvailability(session)
        guard activationState == .activated else { return }
        DispatchQueue.main.async { self.requeueOrphanedHandovers() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshAvailability(session)
    }

    private func refreshAvailability(_ session: WCSession) {
        let available = session.isPaired && session.isWatchAppInstalled
        DispatchQueue.main.async { self.isWatchAvailable = available }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { self.handle(userInfo) }
    }

    private func handle(_ userInfo: [String: Any]) {
        // The watch installed a handover: the grant is its now.
        if userInfo[WatchLink.credentialsAck] != nil {
            let kinds = WatchLink.decodeKinds(userInfo[WatchLink.kinds])
            WatchCredentials.discardParked(kinds)
            for kind in kinds { set(kind, .connected) }
        }
        // The watch's own verdict on the sessions it holds.
        if let status = userInfo[WatchLink.watchStatus] as? [String: String] {
            for kind in Self.handoverKinds where link[kind] != .pending {
                guard let raw = status[kind.rawValue] else {
                    if link[kind] != .none { set(kind, .none) }
                    continue
                }
                set(kind, raw == WatchSessionState.expired.rawValue ? .expired : .connected)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
