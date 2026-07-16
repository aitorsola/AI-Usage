//
//  AppSettingsTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class AppSettingsTests: XCTestCase {
    func testParseDefault() {
        let items = MenuSectionsConfig.parse(MenuSectionsConfig.storageDefault)
        XCTAssertEqual(items.count, MenuSectionID.allCases.count)
        XCTAssertTrue(items.allSatisfy(\.visible))
        XCTAssertEqual(items.map(\.id), [.claude, .openai, .openCode, .deepSeek, .week])
    }

    func testParsePreservesOrderAndVisibility() {
        let items = MenuSectionsConfig.parse("week:0,claude:1")
        XCTAssertEqual(items.first?.id, .week)
        XCTAssertEqual(items.first?.visible, false)
        XCTAssertEqual(items.count, MenuSectionID.allCases.count,
                       "las secciones que falten se añaden visibles al final")
        XCTAssertTrue(items.dropFirst(2).allSatisfy(\.visible))
    }

    func testParseIgnoresGarbageAndDuplicates() {
        let items = MenuSectionsConfig.parse("foo:1,claude:0,claude:1")
        XCTAssertEqual(items.filter { $0.id == .claude }.count, 1)
        XCTAssertEqual(items.first { $0.id == .claude }?.visible, false, "gana la primera aparición")
        XCTAssertEqual(items.count, MenuSectionID.allCases.count)
    }

    func testSerializeRoundtrip() {
        let raw = "openai:0,week:1,claude:0,openCode:1,deepSeek:1"
        let roundtrip = MenuSectionsConfig.serialize(MenuSectionsConfig.parse(raw))
        XCTAssertEqual(roundtrip, raw)
    }
}
