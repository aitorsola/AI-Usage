//
//  iOSSupportTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
import SwiftUI
import AIUsageCore
@testable import AI_Usage

final class iOSSupportTests: XCTestCase {
    private func rgb(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    func testColorHexParsing() {
        let red = rgb(Color(hex: "#FF0000"))
        XCTAssertEqual(red.r, 1, accuracy: 0.01)
        XCTAssertEqual(red.g, 0, accuracy: 0.01)

        let noHash = rgb(Color(hex: "00FF00"))
        XCTAssertEqual(noHash.g, 1, accuracy: 0.01, "funciona con y sin #")
    }

    func testBrandColorsMatchSharedHex() {
        for kind in ProviderKind.allCases {
            let brand = rgb(kind.brand)
            let parsed = rgb(Color(hex: kind.colorHex))
            XCTAssertEqual(brand.r, parsed.r, accuracy: 0.005, "\(kind) rojo")
            XCTAssertEqual(brand.g, parsed.g, accuracy: 0.005, "\(kind) verde")
            XCTAssertEqual(brand.b, parsed.b, accuracy: 0.005, "\(kind) azul")
        }
    }

    func testProviderLoginConstructionIsSafe() {
        // Crear el coordinador no debe abrir sesión ni listener hasta begin().
        let login = ProviderLogin(.anthropic) {}
        XCTAssertNotNil(login)
    }
}
