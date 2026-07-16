//
//  CodexParserTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
import AIUsageCore
@testable import AI_Usage

final class CodexParserTests: XCTestCase {
    private var fixture: URL!
    private let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    private func write(_ lines: [String]) throws {
        try lines.joined(separator: "\n").write(to: fixture, atomically: true, encoding: .utf8)
    }

    func testParsesTokenCountsAndTracksModel() throws {
        try write([
            #"{"timestamp":"2026-07-16T10:00:00.000000+00:00","payload":{"type":"turn_context","model":"gpt-5.1"}}"#,
            #"{"timestamp":"2026-07-16T10:00:30.000000+00:00","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20}}}}"#,
        ])
        let entry = CodexParser.parseFile(url: fixture, cutoff: cutoff)
        XCTAssertEqual(entry.events.count, 1)
        let event = try XCTUnwrap(entry.events.first)
        XCTAssertEqual(event.model, "gpt-5.1", "el modelo viene del turn_context previo")
        XCTAssertEqual(event.input, 60, "el input se reporta sin la parte cacheada")
        XCTAssertEqual(event.cacheRead, 40)
        XCTAssertEqual(event.output, 20)
        let expected = Pricing.openAICost(model: "gpt-5.1", uncachedInput: 60, cachedInput: 40, output: 20)
        XCTAssertEqual(event.cost, expected, accuracy: 0.000001)
    }

    func testCapturesLatestRateLimits() throws {
        try write([
            #"{"timestamp":"2026-07-16T09:00:00.000000+00:00","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1}},"rate_limits":{"primary":{"used_percent":10,"window_minutes":300},"plan_type":"plus"}}}"#,
            #"{"timestamp":"2026-07-16T11:00:00.000000+00:00","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1}},"rate_limits":{"primary":{"used_percent":55,"window_minutes":300},"plan_type":"plus"}}}"#,
        ])
        let entry = CodexParser.parseFile(url: fixture, cutoff: cutoff)
        let rates = try XCTUnwrap(entry.rates)
        XCTAssertEqual(rates.gauges.first?.utilization ?? 0, 55, accuracy: 0.0001,
                       "gana el snapshot de rate limits más reciente")
        XCTAssertEqual(rates.planType, "plus")
    }

    func testRateLimitsSurviveCutoffButEventsDoNot() throws {
        // Línea anterior al cutoff: su evento se descarta, sus rate limits no.
        try write([
            #"{"timestamp":"2020-01-01T00:00:00.000000+00:00","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":5}},"rate_limits":{"primary":{"used_percent":33,"window_minutes":300}}}}"#,
        ])
        let entry = CodexParser.parseFile(url: fixture, cutoff: cutoff)
        XCTAssertTrue(entry.events.isEmpty)
        XCTAssertNotNil(entry.rates, "los límites vigentes se conservan aunque el evento sea viejo")
    }

    func testIgnoresMalformedAndZeroTokenLines() throws {
        try write([
            "garbage line",
            #"{"timestamp":"2026-07-16T10:00:00.000000+00:00","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}}}"#,
        ])
        let entry = CodexParser.parseFile(url: fixture, cutoff: cutoff)
        XCTAssertTrue(entry.events.isEmpty)
    }
}
