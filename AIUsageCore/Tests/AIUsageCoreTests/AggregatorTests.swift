//
//  AggregatorTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class AggregatorTests: XCTestCase {
    private let now = Date()

    private func ev(_ key: String, _ ts: Date, model: String = "claude-sonnet-4-6",
                    input: Int = 100, output: Int = 50, cost: Double = 1.0) -> UsageEvent {
        UsageEvent(key: key, ts: ts, model: model, input: input, output: output,
                   cacheRead: 10, cacheWrite5m: 5, cacheWrite1h: 2, cost: cost)
    }

    func testDeduplicatesByKey() {
        let snap = Aggregator.snapshot(from: [ev("a", now), ev("a", now), ev("b", now)], now: now)
        XCTAssertEqual(snap.today.messages, 2)
    }

    func testPeriodBuckets() {
        let cal = Calendar.current
        let events = [
            ev("today", now),
            ev("d5", cal.date(byAdding: .day, value: -5, to: now)!),
            ev("d20", cal.date(byAdding: .day, value: -20, to: now)!),
            ev("d40", cal.date(byAdding: .day, value: -40, to: now)!),   // fuera de los 30 días
        ]
        let snap = Aggregator.snapshot(from: events, now: now)
        XCTAssertEqual(snap.today.messages, 1)
        XCTAssertEqual(snap.last7.messages, 2)
        XCTAssertEqual(snap.last30.messages, 3)
        XCTAssertEqual(snap.days.count, 30, "siempre 30 días, con huecos a cero")
        XCTAssertEqual(snap.days.map(\.totals.messages).reduce(0, +), 3)
    }

    func testTotalsAccumulate() {
        let snap = Aggregator.snapshot(from: [ev("a", now), ev("b", now)], now: now)
        XCTAssertEqual(snap.today.input, 200)
        XCTAssertEqual(snap.today.output, 100)
        XCTAssertEqual(snap.today.cacheRead, 20)
        XCTAssertEqual(snap.today.cost, 2.0, accuracy: 0.0001)
        XCTAssertEqual(snap.today.totalTokens, 200 + 100 + 20 + 10 + 4)
    }

    func testModelsSortedByCostDescending() {
        let events = [
            ev("a", now, model: "cheap", cost: 1),
            ev("b", now, model: "pricey", cost: 5),
            ev("c", now, model: "mid", cost: 3),
        ]
        let snap = Aggregator.snapshot(from: events, now: now)
        XCTAssertEqual(snap.models.map(\.model), ["pricey", "mid", "cheap"])
    }

    func testFiveHourBlocks() {
        // Dos eventos antiguos juntos (un bloque) y uno reciente (otro bloque).
        let events = [
            ev("old1", now.addingTimeInterval(-20 * 3600), cost: 1),
            ev("old2", now.addingTimeInterval(-19.5 * 3600), cost: 2),
            ev("new1", now.addingTimeInterval(-1 * 3600), cost: 1),
        ]
        let snap = Aggregator.snapshot(from: events, now: now)
        XCTAssertEqual(snap.maxBlockCost, 3.0, accuracy: 0.0001, "el bloque antiguo suma 1+2")
        let block = try! XCTUnwrap(snap.currentBlock, "el bloque de hace 1 h sigue abierto")
        XCTAssertEqual(block.totals.cost, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(block.end, now)
    }

    func testNoCurrentBlockWhenExpired() {
        let snap = Aggregator.snapshot(from: [ev("old", now.addingTimeInterval(-10 * 3600))], now: now)
        XCTAssertNil(snap.currentBlock)
        XCTAssertEqual(snap.maxBlockCost, 1.0, accuracy: 0.0001)
    }
}
