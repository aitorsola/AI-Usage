//
//  CredentialSyncTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

// The watch holds its own token family, handed over once by the phone. These
// cover the payload shapes both sides agree on and the snapshot filtering the
// watch applies to phone pushes — the credential stores themselves are not
// exercised here (they would touch the real keychain/container).
final class CredentialSyncTests: XCTestCase {
    func testKindsFollowThePayload() {
        XCTAssertEqual(WatchCredentials().kinds, [])
        XCTAssertEqual(WatchCredentials(deepSeekKey: "k").kinds, [.deepSeek])
        let both = WatchCredentials(
            anthropic: .init(access: "a", refresh: "r", expiresAt: nil),
            openAI: .init(access: "o", refresh: nil, expiresAt: nil,
                          accountID: nil, planType: nil, email: nil))
        XCTAssertEqual(both.kinds, [.anthropic, .openAI])
    }

    func testKindsRoundTripThroughTheLinkVocabulary() {
        let kinds: Set<ProviderKind> = [.openAI, .anthropic]
        let raw = WatchLink.encodeKinds(kinds)
        XCTAssertEqual(raw, ["anthropic", "openAI"], "sorted, stable on the wire")
        XCTAssertEqual(WatchLink.decodeKinds(raw), kinds)
        XCTAssertEqual(WatchLink.decodeKinds(["bogus"]), [], "unknown kinds are dropped")
        XCTAssertEqual(WatchLink.decodeKinds(nil), [])
    }

    func testPhoneSnapshotIsRestrictedToWhatTheWatchHolds() {
        let snap = WidgetSnapshot(
            providers: [
                WSProvider(name: "Claude", colorHex: "#D97757", subscription: nil,
                           gauges: [WSGauge(label: "s", used: 10)], lines: [], limitReached: nil),
                WSProvider(name: "OpenAI", colorHex: "#10A37F", subscription: nil,
                           gauges: [WSGauge(label: "s", used: 20)], lines: [], limitReached: nil),
            ],
            showRemaining: false, weekTitle: "", weekBars: [], updatedText: "", date: Date())
        let kept = snap.restricted(to: [.anthropic])
        XCTAssertEqual(kept.providers.map(\.name), ["Claude"])
        XCTAssertFalse(kept.showRemaining, "everything but the provider list is preserved")
        XCTAssertTrue(snap.restricted(to: []).providers.isEmpty)
    }

    func testSessionStateWire() {
        XCTAssertEqual(WatchSessionState.expired.rawValue, "expired")
        XCTAssertEqual(WatchSessionState(rawValue: "ok"), .ok)
    }
}
