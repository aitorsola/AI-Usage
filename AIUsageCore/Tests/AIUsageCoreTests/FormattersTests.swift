//
//  FormattersTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class FormattersTests: XCTestCase {
    func testTokens() {
        XCTAssertEqual(Formatters.tokens(999), "999")
        XCTAssertEqual(Formatters.tokens(2_000), String.localizedStringWithFormat("%.0f k", 2.0))
        XCTAssertEqual(Formatters.tokens(2_500_000), String.localizedStringWithFormat("%.1f M", 2.5))
        XCTAssertEqual(Formatters.tokens(3_000_000_000), String.localizedStringWithFormat("%.1f B", 3.0))
    }

    func testCostHasCurrencyPrefixAndTwoDecimals() {
        let s = Formatters.cost(1.5)
        XCTAssertTrue(s.hasPrefix("$"))
        XCTAssertTrue(s.contains("1"))
        XCTAssertTrue(s.hasSuffix("50"), "dos decimales: 1.50")
    }

    func testMoney() {
        XCTAssertEqual(Formatters.money("5.00"), Formatters.cost(5.0))
        XCTAssertEqual(Formatters.money(2.5), Formatters.cost(2.5))
        XCTAssertNil(Formatters.money(nil as String?))
        XCTAssertNil(Formatters.money(""))
        XCTAssertEqual(Formatters.money("EUR 5.00"), "EUR 5.00", "lo no numérico pasa tal cual")
    }

    func testModelName() {
        XCTAssertEqual(Formatters.modelName("claude-sonnet-4-6"), "Sonnet 4.6")
        XCTAssertEqual(Formatters.modelName("claude-opus-4-8"), "Opus 4.8")
        XCTAssertEqual(Formatters.modelName("claude-haiku-4-5-20251001"), "Haiku 4.5",
                       "el sufijo de fecha se filtra")
        XCTAssertEqual(Formatters.modelName("gpt-5"), "gpt-5", "los no-Claude no se tocan")
    }

    func testRemaining() {
        let s = Formatters.remaining(until: Date().addingTimeInterval(2 * 3600 + 90))
        XCTAssertTrue(s.contains("2 h"), "«\(s)» debería contener las horas")
        let m = Formatters.remaining(until: Date().addingTimeInterval(5 * 60 + 30))
        XCTAssertTrue(m.contains("min"))
        XCTAssertEqual(Formatters.remaining(until: Date().addingTimeInterval(-100)), "0 min",
                       "las fechas pasadas no dan negativos")
    }

    func testResetCompact() {
        // +30 s de margen para que ambas llamadas caigan en el mismo minuto.
        let near = Date().addingTimeInterval(3 * 3600 + 30)
        XCTAssertEqual(Formatters.resetCompact(near), Formatters.remaining(until: near))
        let far = Date().addingTimeInterval(3 * 24 * 3600)
        XCTAssertEqual(Formatters.resetCompact(far), Formatters.dayMedium(far))
    }
}
