//
//  WidgetSharedTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class WidgetSharedTests: XCTestCase {
    func testSnapshotCodableRoundtrip() throws {
        let snapshot = WidgetSnapshot(
            providers: [
                WSProvider(name: "Claude", colorHex: "#D97757", subscription: "pro",
                           gauges: [WSGauge(label: "Sesión", used: 42, reset: "2 h 5 min")],
                           lines: ["Hoy $0.82"], limitReached: nil),
            ],
            showRemaining: false,
            weekTitle: "Últimos 7 días",
            weekBars: [0.1, 0.9],
            updatedText: "12:00",
            date: Date(timeIntervalSince1970: 1_800_000_000))

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testGaugeResetDefaultsToNil() {
        XCTAssertNil(WSGauge(label: "x", used: 1).reset)
    }

    func testPlaceholderIsRenderable() {
        let p = WidgetSnapshot.placeholder
        XCTAssertFalse(p.providers.isEmpty)
        XCTAssertEqual(p.providers.first?.gauges.count, 2, "sesión + semana en el placeholder")
        XCTAssertFalse(p.weekBars.isEmpty)
    }

    private func snapshot(used: Double, reset: String?, updated: String = "12:00") -> WidgetSnapshot {
        WidgetSnapshot(
            providers: [WSProvider(name: "Claude", colorHex: "#D97757", subscription: "pro",
                                   gauges: [WSGauge(label: "Sesión", used: used, reset: reset)],
                                   lines: ["Hoy $1"], limitReached: nil)],
            showRemaining: true, weekTitle: "t", weekBars: [0.5],
            updatedText: updated, date: Date(timeIntervalSince1970: 1))
    }

    func testReloadFingerprintIgnoresChurn() {
        // Countdown value, timestamps, cost lines y week bars cambian cada
        // ciclo: no deben provocar recarga.
        let a = snapshot(used: 37.2, reset: "2 h 5 min", updated: "12:00")
        let b = snapshot(used: 37.4, reset: "2 h 4 min", updated: "12:01")
        XCTAssertEqual(a.reloadFingerprint, b.reloadFingerprint)
    }

    func testReloadFingerprintTracksRenderedChanges() {
        let base = snapshot(used: 37, reset: "2 h 5 min")
        // Cambia el % entero mostrado → recarga.
        XCTAssertNotEqual(base.reloadFingerprint,
                          snapshot(used: 38, reset: "2 h 5 min").reloadFingerprint)
        // Aparece/desaparece el label de reset (sesión 5h activa o no) → recarga.
        XCTAssertNotEqual(base.reloadFingerprint,
                          snapshot(used: 37, reset: nil).reloadFingerprint)
    }

    func testReloadFingerprintTracksStatusNotes() {
        let base = snapshot(used: 37, reset: nil)
        var noted = base
        noted.providers[0].note = "Sin sesión"
        XCTAssertNotEqual(base.reloadFingerprint, noted.reloadFingerprint,
                          "cambiar la nota de estado debe repintar el widget")
    }
}
