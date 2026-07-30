//
//  AuthFailureTracker.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// A rejected refresh token is not proof that the session is dead.
//
// The iPhone and the Apple Watch refresh the same token family independently,
// and the provider ROTATES the refresh token on every refresh — so whoever
// refreshes second is handed a rejection for a token the peer just spent. The
// peer hands its fresh copy back over WatchConnectivity, but that delivery is
// queued and takes a moment to arrive.
//
// So a rejection only means "signed out" once it has survived several attempts
// spanning more than a few minutes — long enough for the peer's copy to land.
// Reacting to the first one is what logged the user out every few minutes on
// iOS, while macOS (a single refresher, no watch) never saw it.
enum AuthFailureTracker {
    private static let minimumAttempts = 3
    private static let minimumElapsed: TimeInterval = 10 * 60

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupIdentifier) }
    private static func key(_ service: String) -> String { "authFailure.\(service)" }

    /// Records a rejected refresh. Returns true once the streak is long enough
    /// that the session should be treated as genuinely dead and a real re-login
    /// demanded.
    static func record(_ service: String) -> Bool {
        // macOS refreshes from a single process and shares its token family with
        // nobody, so a rejection there really is a dead session — keep prompting
        // immediately instead of making the user wait out the streak.
        #if os(macOS)
        return true
        #else
        // No shared container (should not happen): fall back to the old,
        // stricter behaviour rather than never asking the user to sign in.
        guard let defaults else { return true }
        let k = key(service)
        var entry = defaults.dictionary(forKey: k) ?? [:]
        let first = entry["first"] as? Date ?? Date()
        let count = (entry["count"] as? Int ?? 0) + 1
        entry["first"] = first
        entry["count"] = count
        defaults.set(entry, forKey: k)
        return count >= minimumAttempts && Date().timeIntervalSince(first) >= minimumElapsed
        #endif
    }

    /// Clears the streak: a refresh succeeded, or fresher credentials arrived
    /// from the paired device.
    static func clear(_ service: String) {
        defaults?.removeObject(forKey: key(service))
    }
}
