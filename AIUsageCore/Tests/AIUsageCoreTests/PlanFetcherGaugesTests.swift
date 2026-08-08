//
//  PlanFetcherGaugesTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class PlanFetcherGaugesTests: XCTestCase {
    // Payload real del endpoint de usage (ago. 2026): junto a los límites de
    // verdad viene un cubo experimental dormido con nombre en clave interno.
    private let usage: [String: Any] = [
        "five_hour": ["utilization": 16.0, "resets_at": "2026-08-08T13:40:00.426968+00:00"],
        "seven_day": ["utilization": 14.0, "resets_at": "2026-08-12T00:00:00.426990+00:00"],
        "seven_day_opus": NSNull(),
        "tangelo": NSNull(),
        "nimbus_quill": ["utilization": 0.0, "resets_at": NSNull(),
                         "limit_dollars": NSNull(), "used_dollars": NSNull()],
    ]

    func testDormantCodenameBucketsAreHidden() {
        let gauges = PlanFetcher.gauges(from: usage)
        XCTAssertEqual(gauges.map(\.key), ["five_hour", "seven_day"],
                       "un cubo sin uso, sin reset y sin dólares no es un límite")
    }

    func testUnknownKeysWithSignsOfLifeStillSurface() {
        // Así aparecieron seven_day_opus y compañía sin tocar código: una clave
        // desconocida PERO con contenido real debe seguir mostrándose.
        var payload = usage
        payload["cinder_cove"] = ["utilization": 42.0]
        payload["amber_ladder"] = ["utilization": 0.0,
                                   "resets_at": "2026-08-12T00:00:00+00:00"]
        payload["iguana_necktie"] = ["utilization": 0.0, "limit_dollars": 25.0]
        let keys = PlanFetcher.gauges(from: payload).map(\.key)
        XCTAssertTrue(keys.contains("cinder_cove"), "uso > 0 → visible")
        XCTAssertTrue(keys.contains("amber_ladder"), "con reset → visible")
        XCTAssertTrue(keys.contains("iguana_necktie"), "con límite en dólares → visible")
        XCTAssertEqual(PlanFetcher.gauges(from: payload).first?.key, "five_hour",
                       "los límites conocidos conservan su orden por delante")
    }

    func testKnownKeysShowEvenWhenIdle() {
        // Un límite CONOCIDO a 0 es información ("no has gastado nada"), no
        // ruido: el filtro de señales de vida solo aplica a desconocidos.
        let payload: [String: Any] = ["five_hour": ["utilization": 0.0]]
        XCTAssertEqual(PlanFetcher.gauges(from: payload).map(\.key), ["five_hour"])
    }
}
