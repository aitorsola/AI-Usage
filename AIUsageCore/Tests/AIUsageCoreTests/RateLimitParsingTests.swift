//
//  RateLimitParsingTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class RateLimitParsingTests: XCTestCase {
    func testParsesPrimaryAndSecondaryWindows() {
        let rl: [String: Any] = [
            "primary": ["used_percent": 37.5, "window_minutes": 300,
                        "resets_at": 1_900_000_000_000],          // milisegundos
            "secondary": ["used_percent": 12, "window_minutes": 10080,
                          "resets_in_seconds": 3600],
            "plan_type": "plus",
        ]
        let out = RateLimitParsing.parseFull(rl)
        XCTAssertEqual(out.gauges.count, 2)
        XCTAssertEqual(out.planType, "plus")

        let primary = out.gauges[0]
        XCTAssertEqual(primary.key, "primary")
        XCTAssertEqual(primary.utilization, 37.5, accuracy: 0.0001)
        XCTAssertEqual(primary.label, L.t("session") + " (5 h)")
        XCTAssertEqual(primary.resetsAt?.timeIntervalSince1970 ?? 0, 1_900_000_000, accuracy: 1,
                       "resets_at en ms se normaliza a segundos")

        let secondary = out.gauges[1]
        XCTAssertEqual(secondary.label, L.t("week"))
        let expected = Date().addingTimeInterval(3600).timeIntervalSince1970
        XCTAssertEqual(secondary.resetsAt?.timeIntervalSince1970 ?? 0, expected, accuracy: 5,
                       "resets_in_seconds se convierte a fecha")
    }

    func testParsesCreditsAndSpendLimit() {
        let rl: [String: Any] = [
            "credits": ["unlimited": false, "balance": "12.34"],
            "individual_limit": ["limit": "50", "used": 20, "remaining_percent": 60,
                                 "resets_at": 1_900_000_000],
        ]
        let out = RateLimitParsing.parseFull(rl)
        XCTAssertEqual(out.credits?.balance, "12.34")
        XCTAssertEqual(out.credits?.unlimited, false)
        XCTAssertEqual(out.spendLimit?.limitText, "50")
        XCTAssertEqual(out.spendLimit?.usedText, "20", "los números se convierten a texto")
        XCTAssertEqual(out.spendLimit?.usedPercent ?? 0, 40, accuracy: 0.0001,
                       "remaining 60% → used 40%")
    }

    func testLimitReachedReasons() {
        let member = RateLimitParsing.parseFull(["rate_limit_reached_type": "member_credits_depleted"])
        XCTAssertEqual(member.limitReachedReason, L.t("your_workspace_credits_are_depleted"))

        let spend = RateLimitParsing.parseFull(["spend_control_reached": true])
        XCTAssertEqual(spend.limitReachedReason, L.t("spending_cap_reached"))

        let none = RateLimitParsing.parseFull([:])
        XCTAssertNil(none.limitReachedReason)
    }

    func testFindRateLimitsAtAnyDepth() {
        let direct: [String: Any] = ["primary": ["used_percent": 1]]
        XCTAssertNotNil(RateLimitParsing.findRateLimits(in: direct))

        let underKey: [String: Any] = ["rate_limits": ["primary": ["used_percent": 1]]]
        XCTAssertNotNil(RateLimitParsing.findRateLimits(in: underKey))

        let nested: [String: Any] = ["whatever": ["secondary": ["used_percent": 2]]]
        XCTAssertNotNil(RateLimitParsing.findRateLimits(in: nested))

        XCTAssertNil(RateLimitParsing.findRateLimits(in: ["unrelated": 1]))
    }

    func testWindowLabels() {
        XCTAssertEqual(RateLimitParsing.windowLabel(minutes: 0), L.t("limit"))
        XCTAssertEqual(RateLimitParsing.windowLabel(minutes: 300), L.t("session") + " (5 h)")
        XCTAssertEqual(RateLimitParsing.windowLabel(minutes: 10080), L.t("week"))
        XCTAssertEqual(RateLimitParsing.windowLabel(minutes: 2880), "2 " + L.t("days"))
        XCTAssertEqual(RateLimitParsing.windowLabel(minutes: 720), "12 h")
    }
}
