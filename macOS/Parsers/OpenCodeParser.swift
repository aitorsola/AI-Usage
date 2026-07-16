//
//  OpenCodeParser.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import AIUsageCore
import SQLite3

struct OpenCodeParser {
    static let defaultDBPath = NSHomeDirectory() + "/.local/share/opencode/opencode.db"

    // Injectable for tests; the app always uses the default location.
    var dbPath = OpenCodeParser.defaultDBPath

    struct Result {
        var events: [UsageEvent]
        var installed: Bool
    }

    func collect(since cutoff: Date) -> Result {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return Result(events: [], installed: false)
        }
        guard let db = open() else { return Result(events: [], installed: true) }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT time_created, model, cost, tokens_input, tokens_output, \
        tokens_reasoning, tokens_cache_read, tokens_cache_write FROM session;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return Result(events: [], installed: true)
        }
        defer { sqlite3_finalize(stmt) }

        var events: [UsageEvent] = []
        var index = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let createdMs = sqlite3_column_int64(stmt, 0)
            let ts = Date(timeIntervalSince1970: Double(createdMs) / 1000)
            index += 1
            if ts < cutoff { continue }
            let modelJSON = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let model = Self.modelName(from: modelJSON)
            let cost = sqlite3_column_double(stmt, 2)
            let input = Int(sqlite3_column_int64(stmt, 3))
            let output = Int(sqlite3_column_int64(stmt, 4))
            let reasoning = Int(sqlite3_column_int64(stmt, 5))
            let cacheRead = Int(sqlite3_column_int64(stmt, 6))
            let cacheWrite = Int(sqlite3_column_int64(stmt, 7))
            events.append(UsageEvent(key: "oc-\(index)-\(createdMs)",
                                     ts: ts,
                                     model: model,
                                     input: input,
                                     output: output + reasoning,
                                     cacheRead: cacheRead,
                                     cacheWrite5m: cacheWrite,
                                     cacheWrite1h: 0,
                                     cost: cost))
        }
        return Result(events: events, installed: true)
    }

    private func open() -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        for uri in ["file:\(dbPath)?mode=ro", "file:\(dbPath)?mode=ro&immutable=1"] {
            if sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK { return db }
            if let db { sqlite3_close(db) }
            db = nil
        }
        return nil
    }

    static func modelName(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else {
            return json.isEmpty ? "unknown" : json
        }
        if let provider = obj["providerID"] as? String { return "\(provider)/\(id)" }
        return id
    }
}
