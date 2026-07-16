//
//  DemoDataTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
import AIUsageCore
@testable import AI_Usage

final class DemoDataTests: XCTestCase {
    func testDemoDataIsPrivacySafeAndComplete() {
        let demo = DemoData.make()

        // Los cuatro proveedores presentes y disponibles.
        for provider in [demo.anthropic, demo.openAI, demo.openCode, demo.deepSeek] {
            XCTAssertTrue(provider.available)
        }

        // Plan modesto, nunca el real.
        XCTAssertEqual(demo.anthropic.plan.subscription, "pro")
        XCTAssertEqual(demo.openAI.plan.subscription, "plus")

        // Barras de límite llenas: utilización 0 (100% restante).
        for gauge in demo.anthropic.plan.gauges + demo.openAI.plan.gauges {
            XCTAssertEqual(gauge.utilization, 0, "las capturas muestran los límites intactos")
            XCTAssertNotNil(gauge.resetsAt)
        }

        // Costes modestos.
        XCTAssertLessThan(demo.anthropic.snapshot.today.cost, 1.0)
        XCTAssertLessThan(demo.anthropic.snapshot.last30.cost, 20.0)

        // Saldo DeepSeek discreto.
        XCTAssertEqual(demo.deepSeek.plan.credits?.balance, "5.00")

        // 14 días de histórico para la vista diaria.
        XCTAssertEqual(demo.anthropic.snapshot.days.count, 14)
        XCTAssertEqual(demo.openAI.snapshot.days.count, 14)

        // Bloque de 5h vigente para que la tarjeta no salga vacía.
        XCTAssertNotNil(demo.anthropic.snapshot.currentBlock)
    }
}
