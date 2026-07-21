//
//  PlatformStatusTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class PlatformStatusTests: XCTestCase {
    func testIndicatorMapping() {
        XCTAssertEqual(PlatformHealth(indicator: "none"), .operational)
        XCTAssertEqual(PlatformHealth(indicator: "minor"), .degraded)
        XCTAssertEqual(PlatformHealth(indicator: "major"), .outage)
        XCTAssertEqual(PlatformHealth(indicator: "critical"), .outage)
        XCTAssertEqual(PlatformHealth(indicator: "maintenance"), .maintenance)
        XCTAssertEqual(PlatformHealth(indicator: "NONE"), .operational, "case-insensitive")
        XCTAssertNil(PlatformHealth(indicator: "wat"))
    }

    func testOnlyProblemsAreNoteworthy() {
        XCTAssertFalse(PlatformHealth.operational.isNoteworthy)
        XCTAssertTrue(PlatformHealth.degraded.isNoteworthy)
        XCTAssertTrue(PlatformHealth.outage.isNoteworthy)
        XCTAssertTrue(PlatformHealth.maintenance.isNoteworthy)
    }

    func testStatusPagesOnlyForProvidersThatHaveOne() {
        XCTAssertNotNil(ProviderKind.anthropic.statusURL)
        XCTAssertNotNil(ProviderKind.openAI.statusURL)
        XCTAssertNil(ProviderKind.deepSeek.statusURL)
        XCTAssertNil(ProviderKind.openCode.statusURL)
    }

    func testCodableWithinSnapshot() throws {
        let snap = WidgetSnapshot(
            providers: [WSProvider(name: "Claude", colorHex: "#D97757", subscription: nil,
                                   gauges: [], lines: [], limitReached: nil, health: .degraded)],
            showRemaining: true, weekTitle: "", weekBars: [], updatedText: "", date: Date())
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snap))
        XCTAssertEqual(decoded.providers.first?.health, .degraded)
    }
}
