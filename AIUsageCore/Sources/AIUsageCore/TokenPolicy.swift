//
//  TokenPolicy.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// When to spend a refresh. Pure so the rules are testable; both OAuth
// providers share them.
//
// One token family per device (the watch holds its own grant, handed over by
// the iPhone), refreshed by the app and its extension under a cross-process
// lock — so a refresh token is never spent twice and a rejection is a genuinely
// dead session. Two things keep those refreshes rare and safe:
//
// - The APP refreshes proactively while the token still has `proactiveWindow`
//   left (hours). Extensions pass 0: they only refresh what is already expired,
//   so the process most likely to be suspended mid-request almost never has to.
// - A 401 from a usage endpoint before the local expiry (the provider does
//   that) forces one refresh of that exact token instead of a "sign in again".
public enum TokenPolicy {
    /// Below this margin the token counts as expired, matching the providers'
    /// own tolerance for a request that lands just before expiry.
    public static let expiryMargin: TimeInterval = 60

    /// True while the token can still authenticate a request.
    public static func isUsable(expiresAt: Date?, now: Date = Date()) -> Bool {
        expiresAt.map { $0 > now.addingTimeInterval(expiryMargin) } ?? true
    }

    /// True when a refresh should be attempted now: the token is unusable, the
    /// server just rejected this very access token (`rejected`), or the caller
    /// wants it renewed ahead of time (`proactiveWindow` > 0 and less than that
    /// is left). Undated tokens are only refreshed when rejected.
    public static func shouldRefresh(expiresAt: Date?, proactiveWindow: TimeInterval = 0,
                                     rejected: Bool = false, now: Date = Date()) -> Bool {
        if rejected { return true }
        guard let expiresAt else { return false }
        if !isUsable(expiresAt: expiresAt, now: now) { return true }
        return proactiveWindow > 0 && expiresAt <= now.addingTimeInterval(proactiveWindow)
    }
}
