//
//  Pricing.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

enum Pricing {
    struct Rates {
        let input: Double
        let output: Double
    }

    static func rates(for model: String) -> Rates {
        let m = model.lowercased()
        if m.contains("fable") || m.contains("mythos") { return Rates(input: 10, output: 50) }
        if m.contains("opus-4-1") || m.contains("opus-4-0") || m.contains("opus-4-2025") || m.contains("3-opus") {
            return Rates(input: 15, output: 75)
        }
        if m.contains("opus") { return Rates(input: 5, output: 25) }
        if m.contains("haiku-3-5") || m.contains("3-5-haiku") { return Rates(input: 0.8, output: 4) }
        if m.contains("3-haiku") { return Rates(input: 0.25, output: 1.25) }
        if m.contains("haiku") { return Rates(input: 1, output: 5) }
        return Rates(input: 3, output: 15)
    }

    static func cost(model: String, input: Int, output: Int, cacheRead: Int, w5m: Int, w1h: Int) -> Double {
        let r = rates(for: model)
        let inPerTok = r.input / 1_000_000
        return Double(input) * inPerTok
            + Double(output) * r.output / 1_000_000
            + Double(cacheRead) * inPerTok * 0.1
            + Double(w5m) * inPerTok * 1.25
            + Double(w1h) * inPerTok * 2.0
    }

    struct OpenAIRates {
        let input: Double
        let cachedInput: Double
        let output: Double
    }

    static func openAIRates(for model: String) -> OpenAIRates {
        let m = model.lowercased()
        if m.contains("nano") { return OpenAIRates(input: 0.05, cachedInput: 0.005, output: 0.40) }
        if m.contains("gpt-5"), m.contains("mini") { return OpenAIRates(input: 0.25, cachedInput: 0.025, output: 2) }
        if m.contains("gpt-4.1-mini") { return OpenAIRates(input: 0.40, cachedInput: 0.10, output: 1.60) }
        if m.contains("gpt-4.1") { return OpenAIRates(input: 2, cachedInput: 0.50, output: 8) }
        if m.contains("gpt-4o-mini") { return OpenAIRates(input: 0.15, cachedInput: 0.075, output: 0.60) }
        if m.contains("gpt-4o") { return OpenAIRates(input: 2.5, cachedInput: 1.25, output: 10) }
        if m.contains("o4-mini") { return OpenAIRates(input: 1.10, cachedInput: 0.275, output: 4.40) }
        if m.hasPrefix("o3") { return OpenAIRates(input: 2, cachedInput: 0.50, output: 8) }
        return OpenAIRates(input: 1.25, cachedInput: 0.125, output: 10)
    }

    static func openAICost(model: String, uncachedInput: Int, cachedInput: Int, output: Int) -> Double {
        let r = openAIRates(for: model)
        return (Double(uncachedInput) * r.input
            + Double(cachedInput) * r.cachedInput
            + Double(output) * r.output) / 1_000_000
    }
}
