//
//  OAuthError.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

enum OAuthError {
    // True when a token refresh failed because the refresh token itself was
    // rejected (the session is genuinely dead and a real re-login is needed),
    // as opposed to a transient network or server error — where the session
    // must be KEPT and retried, not reported as "expired". Access tokens are
    // short-lived, so refresh runs constantly; treating every hiccup as a dead
    // session logged the user out every few minutes.
    static func isAuthFailure(_ error: String?) -> Bool {
        guard let e = error?.lowercased() else { return false }
        return e.hasPrefix("http 400") || e.hasPrefix("http 401") || e.hasPrefix("http 403")
            || e.contains("invalid_grant") || e.contains("invalid_token")
            || e.contains("invalid_request") || e.contains("unauthorized")
    }
}
