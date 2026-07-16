//
//  ModelsTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class ModelsTests: XCTestCase {
    private func gauge(_ key: String) -> PlanGauge {
        PlanGauge(key: key, label: key, utilization: 50, resetsAt: nil)
    }

    func testMenuGaugesPreferredOrderAnthropic() {
        var data = ProviderData(kind: .anthropic)
        data.plan.gauges = [gauge("seven_day_opus"), gauge("seven_day"), gauge("five_hour")]
        XCTAssertEqual(data.menuGauges.map(\.key), ["five_hour", "seven_day"],
                       "sesión y semana, en ese orden, ignorando el resto")
    }

    func testMenuGaugesPreferredOrderOpenAI() {
        var data = ProviderData(kind: .openAI)
        data.plan.gauges = [gauge("secondary"), gauge("primary")]
        XCTAssertEqual(data.menuGauges.map(\.key), ["primary", "secondary"])
    }

    func testMenuGaugesFallsBackToFirstTwo() {
        var data = ProviderData(kind: .anthropic)
        data.plan.gauges = [gauge("alpha"), gauge("beta"), gauge("gamma")]
        XCTAssertEqual(data.menuGauges.map(\.key), ["alpha", "beta"])
    }

    func testPrimaryGauge() {
        var claude = ProviderData(kind: .anthropic)
        claude.plan.gauges = [gauge("seven_day"), gauge("five_hour")]
        XCTAssertEqual(claude.primaryGauge?.key, "five_hour")

        var openai = ProviderData(kind: .openAI)
        openai.plan.gauges = [gauge("secondary"), gauge("primary")]
        XCTAssertEqual(openai.primaryGauge?.key, "primary")

        var fallback = ProviderData(kind: .openAI)
        fallback.plan.gauges = [gauge("whatever")]
        XCTAssertEqual(fallback.primaryGauge?.key, "whatever")
    }

    func testTokenTotals() {
        var totals = TokenTotals()
        totals.add(UsageEvent(key: "k", ts: Date(), model: "m", input: 10, output: 20,
                              cacheRead: 30, cacheWrite5m: 5, cacheWrite1h: 1, cost: 0.5))
        XCTAssertEqual(totals.messages, 1)
        XCTAssertEqual(totals.totalTokens, 66)
        XCTAssertEqual(totals.cacheWrite, 6)
    }

    func testPlanStatusHasExtras() {
        XCTAssertFalse(PlanStatus().hasExtras)
        XCTAssertTrue(PlanStatus(credits: CreditsInfo(unlimited: true, balance: nil)).hasExtras)
        XCTAssertTrue(PlanStatus(extraUsage: ExtraUsage(utilization: 1, usedCredits: nil, monthlyLimit: nil)).hasExtras)
    }

    func testBlockInfoEnd() {
        let start = Date()
        XCTAssertEqual(BlockInfo(start: start, lastActivity: start).end,
                       start.addingTimeInterval(5 * 3600))
    }

    func testProviderKindBasics() {
        XCTAssertEqual(ProviderKind.anthropic.name, "Claude")
        XCTAssertFalse(ProviderKind.deepSeek.hasLocalUsage)
        for kind in ProviderKind.allCases {
            XCTAssertTrue(kind.colorHex.hasPrefix("#"))
            XCTAssertEqual(kind.colorHex.count, 7)
        }
    }
}
