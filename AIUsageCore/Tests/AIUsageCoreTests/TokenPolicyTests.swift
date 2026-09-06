//
//  TokenPolicyTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class TokenPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testUsableUntilTheMargin() {
        XCTAssertTrue(TokenPolicy.isUsable(expiresAt: now.addingTimeInterval(3600), now: now))
        XCTAssertFalse(TokenPolicy.isUsable(expiresAt: now.addingTimeInterval(30), now: now),
                       "inside the 60 s margin counts as expired")
        XCTAssertFalse(TokenPolicy.isUsable(expiresAt: now.addingTimeInterval(-1), now: now))
        XCTAssertTrue(TokenPolicy.isUsable(expiresAt: nil, now: now), "undated tokens are trusted")
    }

    func testExpiredTokensRefresh() {
        XCTAssertTrue(TokenPolicy.shouldRefresh(expiresAt: now.addingTimeInterval(10), now: now))
        XCTAssertFalse(TokenPolicy.shouldRefresh(expiresAt: now.addingTimeInterval(8 * 3600), now: now))
    }

    func testProactiveWindowRenewsAhead() {
        let soon = now.addingTimeInterval(90 * 60)
        XCTAssertFalse(TokenPolicy.shouldRefresh(expiresAt: soon, proactiveWindow: 0, now: now),
                       "extensions (window 0) leave a token with 90 min alone")
        XCTAssertTrue(TokenPolicy.shouldRefresh(expiresAt: soon, proactiveWindow: 2 * 3600, now: now),
                      "the app renews ahead of time")
        XCTAssertFalse(TokenPolicy.shouldRefresh(expiresAt: now.addingTimeInterval(7 * 3600),
                                                 proactiveWindow: 2 * 3600, now: now))
    }

    func testRejectedTokenAlwaysRefreshes() {
        // A 401 before the local expiry must force a refresh instead of a
        // "sign in again" that lasts until the local clock catches up.
        XCTAssertTrue(TokenPolicy.shouldRefresh(expiresAt: now.addingTimeInterval(5 * 3600),
                                                rejected: true, now: now))
        XCTAssertTrue(TokenPolicy.shouldRefresh(expiresAt: nil, rejected: true, now: now))
        XCTAssertFalse(TokenPolicy.shouldRefresh(expiresAt: nil, proactiveWindow: 3600, now: now),
                       "undated tokens are only refreshed when rejected")
    }
}
