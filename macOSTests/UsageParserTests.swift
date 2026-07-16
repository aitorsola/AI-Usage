//
//  UsageParserTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
import AIUsageCore
@testable import AI_Usage

final class UsageParserTests: XCTestCase {
    private let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

    private func line(ts: String = "2026-07-16T10:00:00.123456+00:00",
                      model: String = "claude-sonnet-4-6",
                      usage: String = #"{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":10,"cache_creation":{"ephemeral_5m_input_tokens":5,"ephemeral_1h_input_tokens":2}}"#) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","requestId":"req1","uuid":"u1","message":{"id":"msg1","model":"\#(model)","usage":\#(usage)}}"#
    }

    func testParsesAssistantLine() throws {
        let event = try XCTUnwrap(UsageParser.parseLine(line(), cutoff: cutoff))
        XCTAssertEqual(event.model, "claude-sonnet-4-6")
        XCTAssertEqual(event.input, 100)
        XCTAssertEqual(event.output, 50)
        XCTAssertEqual(event.cacheRead, 10)
        XCTAssertEqual(event.cacheWrite5m, 5)
        XCTAssertEqual(event.cacheWrite1h, 2)
        XCTAssertEqual(event.key, "msg1:req1", "id de mensaje + requestId para deduplicar")
        let expected = Pricing.cost(model: "claude-sonnet-4-6", input: 100, output: 50,
                                    cacheRead: 10, w5m: 5, w1h: 2)
        XCTAssertEqual(event.cost, expected, accuracy: 0.000001)
    }

    func testRejectsSyntheticAndNonAssistant() {
        XCTAssertNil(UsageParser.parseLine(line(model: "<synthetic>"), cutoff: cutoff))
        let user = line().replacingOccurrences(of: #""type":"assistant""#, with: #""type":"user""#)
        XCTAssertNil(UsageParser.parseLine(user, cutoff: cutoff), "solo cuentan turnos assistant")
        XCTAssertNil(UsageParser.parseLine("not json at all", cutoff: cutoff))
    }

    func testRejectsBeforeCutoffAndZeroTokens() {
        XCTAssertNil(UsageParser.parseLine(line(ts: "2020-01-01T00:00:00.000000+00:00"), cutoff: cutoff))
        let empty = line(usage: #"{"input_tokens":0,"output_tokens":0}"#)
        XCTAssertNil(UsageParser.parseLine(empty, cutoff: cutoff))
    }

    func testParsesTimestampWithoutFractionalSeconds() {
        XCTAssertNotNil(UsageParser.parseLine(line(ts: "2026-07-16T10:00:00Z"), cutoff: cutoff))
    }

    func testTokensSumsIterations() {
        let usage: [String: Any] = ["iterations": [
            ["input_tokens": 10, "output_tokens": 5, "cache_read_input_tokens": 1,
             "cache_creation": ["ephemeral_5m_input_tokens": 2, "ephemeral_1h_input_tokens": 3]],
            ["input_tokens": 20, "output_tokens": 15, "cache_creation_input_tokens": 7],
        ]]
        let t = UsageParser.tokens(from: usage)
        XCTAssertEqual(t.input, 30)
        XCTAssertEqual(t.output, 20)
        XCTAssertEqual(t.read, 1)
        XCTAssertEqual(t.w5m, 9, "cache_creation desglosado + plano se suman en 5m")
        XCTAssertEqual(t.w1h, 3)
    }

    func testTokensFlatCacheCreationFallsBackTo5m() {
        let t = UsageParser.tokens(from: ["input_tokens": 1, "cache_creation_input_tokens": 42])
        XCTAssertEqual(t.w5m, 42)
        XCTAssertEqual(t.w1h, 0)
    }
}
