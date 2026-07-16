//
//  WidgetSharedTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class WidgetSharedTests: XCTestCase {
    func testSnapshotCodableRoundtrip() throws {
        let snapshot = WidgetSnapshot(
            providers: [
                WSProvider(name: "Claude", colorHex: "#D97757", subscription: "pro",
                           gauges: [WSGauge(label: "Sesión", used: 42, reset: "2 h 5 min")],
                           lines: ["Hoy $0.82"], limitReached: nil),
            ],
            showRemaining: false,
            weekTitle: "Últimos 7 días",
            weekBars: [0.1, 0.9],
            updatedText: "12:00",
            date: Date(timeIntervalSince1970: 1_800_000_000))

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testGaugeResetDefaultsToNil() {
        XCTAssertNil(WSGauge(label: "x", used: 1).reset)
    }

    func testPlaceholderIsRenderable() {
        let p = WidgetSnapshot.placeholder
        XCTAssertFalse(p.providers.isEmpty)
        XCTAssertEqual(p.providers.first?.gauges.count, 2, "sesión + semana en el placeholder")
        XCTAssertFalse(p.weekBars.isEmpty)
    }
}
