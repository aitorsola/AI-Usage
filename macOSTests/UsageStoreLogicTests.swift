//
//  UsageStoreLogicTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
import AIUsageCore
@testable import AI_Usage

final class UsageStoreLogicTests: XCTestCase {
    private func day(_ offset: Int, cost: Double) -> DayUsage {
        var totals = TokenTotals()
        totals.cost = cost
        totals.messages = 1
        return DayUsage(day: Date(timeIntervalSince1970: Double(offset) * 86_400), totals: totals)
    }

    func testCombineDaysMergesCosts() {
        let a = [day(0, cost: 1), day(1, cost: 2)]
        let b = [day(0, cost: 0.5), day(1, cost: 0)]
        let combined = UsageStore.combineDays(a, b)
        XCTAssertEqual(combined.count, 2)
        XCTAssertEqual(combined[0].totals.cost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(combined[1].totals.cost, 2.0, accuracy: 0.0001)
        XCTAssertEqual(combined[0].totals.messages, 2)
    }

    func testCombineDaysFallsBackWhenSecondSeriesIsEmptyOrZero() {
        let a = [day(0, cost: 1)]
        XCTAssertEqual(UsageStore.combineDays(a, []).map(\.totals.cost), [1])
        // Serie del mismo tamaño pero sin coste: no aporta nada.
        XCTAssertEqual(UsageStore.combineDays(a, [day(0, cost: 0)]).map(\.totals.cost), [1])
        // Tamaños distintos: no se puede zipear con seguridad.
        XCTAssertEqual(UsageStore.combineDays(a, [day(0, cost: 1), day(1, cost: 1)]).count, 1)
    }

    func testTokenTotalsAbsorb() {
        var a = TokenTotals()
        a.input = 10; a.cost = 1; a.messages = 2
        var b = TokenTotals()
        b.input = 5; b.output = 7; b.cost = 0.5; b.messages = 1
        a.absorb(b)
        XCTAssertEqual(a.input, 15)
        XCTAssertEqual(a.output, 7)
        XCTAssertEqual(a.cost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(a.messages, 3)
    }
}
