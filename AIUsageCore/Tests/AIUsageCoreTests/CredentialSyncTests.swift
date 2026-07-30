//
//  CredentialSyncTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

// The iPhone and the watch refresh the same rotating token family, so the
// copy with the later expiry is the only live one. These cover the rules that
// decide whether an incoming copy replaces the local one — the keychain writes
// themselves are not exercised here (they would touch the real keychain).
final class CredentialSyncTests: XCTestCase {
    func testFresherCredentialsWin() {
        let now = Date()
        XCTAssertTrue(WatchCredentials.isFresher(now.addingTimeInterval(60), than: now),
                      "a later expiry means the peer rotated after us")
        XCTAssertFalse(WatchCredentials.isFresher(now, than: now.addingTimeInterval(60)),
                       "never downgrade to an older copy")
        XCTAssertFalse(WatchCredentials.isFresher(now, than: now),
                       "an identical expiry is not fresher — nothing to do")
    }

    func testMissingExpiryNeverOverwritesButFillsAGap() {
        let now = Date()
        XCTAssertFalse(WatchCredentials.isFresher(nil, than: now),
                       "an undated copy must not replace a dated one")
        XCTAssertTrue(WatchCredentials.isFresher(now, than: nil),
                      "nothing stored yet: take what the peer has")
    }

    func testIdentityTracksTheRotatingSecretOnly() {
        let base = WatchCredentials(
            anthropic: .init(access: "a1", refresh: "r1", expiresAt: Date()),
            openAI: nil, deepSeekKey: nil)
        // A plain access-token refresh must not look like a new secret, or the
        // devices would hand credentials back and forth on every cycle.
        let sameSecret = WatchCredentials(
            anthropic: .init(access: "a2", refresh: "r1", expiresAt: Date().addingTimeInterval(99)),
            openAI: nil, deepSeekKey: nil)
        let rotated = WatchCredentials(
            anthropic: .init(access: "a2", refresh: "r2", expiresAt: Date()),
            openAI: nil, deepSeekKey: nil)

        XCTAssertEqual(base.identity, sameSecret.identity)
        XCTAssertNotEqual(base.identity, rotated.identity)
    }

    func testIsEmptyGatesTheHandover() {
        XCTAssertTrue(WatchCredentials().isEmpty, "nothing to hand over")
        XCTAssertFalse(WatchCredentials(deepSeekKey: "k").isEmpty)
    }
}
