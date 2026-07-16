//
//  PricingTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class PricingTests: XCTestCase {
    func testClaudeRateSelection() {
        XCTAssertEqual(Pricing.rates(for: "claude-fable-5").input, 10)
        XCTAssertEqual(Pricing.rates(for: "claude-opus-4-8").input, 5)
        XCTAssertEqual(Pricing.rates(for: "claude-3-opus-20240229").input, 15)
        XCTAssertEqual(Pricing.rates(for: "claude-haiku-4-5").input, 1)
        XCTAssertEqual(Pricing.rates(for: "claude-3-5-haiku-20241022").input, 0.8)
        XCTAssertEqual(Pricing.rates(for: "claude-sonnet-4-6").input, 3, "sonnet es la tarifa por defecto")
    }

    func testClaudeCostMath() {
        let model = "claude-sonnet-4-6"   // 3 / 15 por millón
        XCTAssertEqual(Pricing.cost(model: model, input: 1_000_000, output: 0, cacheRead: 0, w5m: 0, w1h: 0),
                       3.0, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: model, input: 0, output: 1_000_000, cacheRead: 0, w5m: 0, w1h: 0),
                       15.0, accuracy: 0.0001)
        // Multiplicadores de caché: lectura 0.1×, escritura 5m 1.25×, escritura 1h 2×.
        XCTAssertEqual(Pricing.cost(model: model, input: 0, output: 0, cacheRead: 1_000_000, w5m: 0, w1h: 0),
                       0.3, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: model, input: 0, output: 0, cacheRead: 0, w5m: 1_000_000, w1h: 0),
                       3.75, accuracy: 0.0001)
        XCTAssertEqual(Pricing.cost(model: model, input: 0, output: 0, cacheRead: 0, w5m: 0, w1h: 1_000_000),
                       6.0, accuracy: 0.0001)
    }

    func testOpenAIRateSelection() {
        XCTAssertEqual(Pricing.openAIRates(for: "gpt-5-nano").input, 0.05)
        XCTAssertEqual(Pricing.openAIRates(for: "gpt-5-mini").input, 0.25)
        XCTAssertEqual(Pricing.openAIRates(for: "gpt-4o").input, 2.5)
        XCTAssertEqual(Pricing.openAIRates(for: "o3").input, 2)
        XCTAssertEqual(Pricing.openAIRates(for: "gpt-5").input, 1.25, "gpt-5 es la tarifa por defecto")
    }

    func testOpenAICostMath() {
        // gpt-5: 1.25 / 0.125 / 10 por millón
        XCTAssertEqual(Pricing.openAICost(model: "gpt-5", uncachedInput: 1_000_000, cachedInput: 0, output: 0),
                       1.25, accuracy: 0.0001)
        XCTAssertEqual(Pricing.openAICost(model: "gpt-5", uncachedInput: 0, cachedInput: 1_000_000, output: 0),
                       0.125, accuracy: 0.0001)
        XCTAssertEqual(Pricing.openAICost(model: "gpt-5", uncachedInput: 0, cachedInput: 0, output: 1_000_000),
                       10.0, accuracy: 0.0001)
    }
}
