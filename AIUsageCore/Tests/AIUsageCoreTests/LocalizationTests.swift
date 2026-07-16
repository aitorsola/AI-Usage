//
//  LocalizationTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class LocalizationTests: XCTestCase {
    func testKnownKeyResolves() {
        XCTAssertNotEqual(L.t("week"), "week", "una clave conocida devuelve traducción, no la clave")
    }

    func testUnknownKeyFallsBackToKey() {
        XCTAssertEqual(L.t("nonexistent_key_xyz"), "nonexistent_key_xyz")
    }

    func testAllLanguagesHaveTheSameKeys() {
        let en = Set(Translations.tables[.en]!.keys)
        XCTAssertFalse(en.isEmpty)
        for (lang, table) in Translations.tables where lang != .en {
            let keys = Set(table.keys)
            let missing = en.subtracting(keys).sorted()
            let extra = keys.subtracting(en).sorted()
            XCTAssertEqual(missing, [], "faltan claves en \(lang.rawValue)")
            XCTAssertEqual(extra, [], "claves sobrantes en \(lang.rawValue) que no existen en en")
        }
    }

    func testFormatPlaceholdersMatchAcrossLanguages() {
        // Las claves con %@ / %d en inglés deben conservar el mismo número
        // de marcadores en todos los idiomas, o String(format:) fallará.
        let en = Translations.tables[.en]!
        func count(_ s: String) -> Int {
            s.components(separatedBy: "%@").count - 1 + s.components(separatedBy: "%d").count - 1
        }
        for (key, value) in en where count(value) > 0 {
            for (lang, table) in Translations.tables {
                guard let translated = table[key] else { continue }
                XCTAssertEqual(count(translated), count(value),
                               "\(lang.rawValue).\(key) tiene distinto número de %@/%d")
            }
        }
    }
}
