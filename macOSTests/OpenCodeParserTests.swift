//
//  OpenCodeParserTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
import SQLite3
import AIUsageCore
@testable import AI_Usage

final class OpenCodeParserTests: XCTestCase {
    private var dbPath: String!
    private let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-\(UUID().uuidString).db").path

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let recent = Int64(1_800_000_000_000)   // ms, posterior al cutoff
        let old = Int64(1_500_000_000_000)      // ms, anterior al cutoff
        let schema = """
        CREATE TABLE session (time_created INTEGER, model TEXT, cost REAL,
            tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER,
            tokens_cache_read INTEGER, tokens_cache_write INTEGER);
        INSERT INTO session VALUES (\(recent),
            '{"providerID":"anthropic","id":"claude-sonnet-4-6"}',
            1.25, 100, 40, 10, 30, 20);
        INSERT INTO session VALUES (\(old), '{"id":"gpt-5"}', 9.99, 1, 1, 0, 0, 0);
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testReadsSessionsAndAppliesCutoff() throws {
        var parser = OpenCodeParser()
        parser.dbPath = dbPath
        let result = parser.collect(since: cutoff)

        XCTAssertTrue(result.installed)
        XCTAssertEqual(result.events.count, 1, "la sesión antigua queda fuera del cutoff")

        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(event.model, "anthropic/claude-sonnet-4-6")
        XCTAssertEqual(event.input, 100)
        XCTAssertEqual(event.output, 50, "output + reasoning")
        XCTAssertEqual(event.cacheRead, 30)
        XCTAssertEqual(event.cacheWrite5m, 20)
        XCTAssertEqual(event.cost, 1.25, accuracy: 0.0001,
                       "el coste lo reporta OpenCode y se usa tal cual")
        XCTAssertEqual(event.ts.timeIntervalSince1970, 1_800_000_000, accuracy: 1,
                       "time_created en ms se normaliza a segundos")
    }

    func testMissingDatabaseMeansNotInstalled() {
        var parser = OpenCodeParser()
        parser.dbPath = "/nonexistent/opencode.db"
        let result = parser.collect(since: cutoff)
        XCTAssertFalse(result.installed)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testModelNameDecoding() {
        XCTAssertEqual(OpenCodeParser.modelName(from: #"{"providerID":"openai","id":"gpt-5"}"#),
                       "openai/gpt-5")
        XCTAssertEqual(OpenCodeParser.modelName(from: #"{"id":"gpt-5"}"#), "gpt-5")
        XCTAssertEqual(OpenCodeParser.modelName(from: "plain-text"), "plain-text",
                       "lo que no es JSON pasa tal cual")
        XCTAssertEqual(OpenCodeParser.modelName(from: ""), "unknown")
    }
}
