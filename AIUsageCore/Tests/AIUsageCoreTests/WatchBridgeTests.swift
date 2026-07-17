//
//  WatchBridgeTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class WatchBridgeTests: XCTestCase {
    private func plan(gaugeKeys: [String] = [], needsLogin: Bool = false,
                      subscription: String? = nil, balance: String? = nil) -> PlanStatus {
        PlanStatus(gauges: gaugeKeys.map {
                       PlanGauge(key: $0, label: $0, utilization: 42,
                                 resetsAt: Date().addingTimeInterval(3600))
                   },
                   subscription: subscription, needsLogin: needsLogin,
                   credits: balance.map { CreditsInfo(unlimited: false, balance: $0) })
    }

    func testBuilderSkipsProvidersThatNeedLogin() {
        let snap = SnapshotBuilder.network(anthropic: plan(gaugeKeys: ["five_hour", "seven_day"]),
                                           openAI: plan(needsLogin: true),
                                           deepSeek: plan(needsLogin: true),
                                           showRemaining: true)
        XCTAssertEqual(snap.providers.map(\.name), ["Claude"])
        XCTAssertTrue(snap.showRemaining)
    }

    func testBuilderKeepsFixedOrderAndMapsGauges() {
        let snap = SnapshotBuilder.network(anthropic: plan(gaugeKeys: ["seven_day", "five_hour"], subscription: "pro"),
                                           openAI: plan(gaugeKeys: ["primary", "secondary"]),
                                           deepSeek: plan(balance: "5.00"),
                                           showRemaining: false)
        XCTAssertEqual(snap.providers.map(\.name), ["Claude", "OpenAI", "DeepSeek"])
        XCTAssertFalse(snap.showRemaining)

        let claude = snap.providers[0]
        XCTAssertEqual(claude.subscription, "pro")
        XCTAssertEqual(claude.gauges.map(\.label), ["five_hour", "seven_day"],
                       "menuGauges reordena: sesión primero")
        XCTAssertEqual(claude.gauges.first?.used ?? 0, 42, accuracy: 0.0001)
        XCTAssertNotNil(claude.gauges.first?.reset, "el reset viaja como texto compacto")

        let deepSeek = snap.providers[2]
        XCTAssertEqual(deepSeek.lines.count, 1, "el saldo va como línea")
    }

    func testCredentialsCodableRoundtrip() throws {
        let creds = WatchCredentials(
            anthropic: .init(access: "a-token", refresh: "a-refresh",
                             expiresAt: Date(timeIntervalSince1970: 1_900_000_000)),
            openAI: .init(access: "o-token", refresh: nil, expiresAt: nil,
                          accountID: "acc_1", planType: "plus", email: "x@y.z"),
            deepSeekKey: "sk-123")
        let decoded = try JSONDecoder().decode(WatchCredentials.self,
                                               from: JSONEncoder().encode(creds))
        XCTAssertEqual(decoded.anthropic?.access, "a-token")
        XCTAssertEqual(decoded.anthropic?.refresh, "a-refresh")
        XCTAssertEqual(decoded.openAI?.accountID, "acc_1")
        XCTAssertEqual(decoded.openAI?.planType, "plus")
        XCTAssertEqual(decoded.deepSeekKey, "sk-123")
        XCTAssertFalse(decoded.isEmpty)
        XCTAssertTrue(WatchCredentials().isEmpty)
    }
}
