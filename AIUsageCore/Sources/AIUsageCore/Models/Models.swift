//
//  Models.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

public struct UsageEvent {
    public let key: String
    public let ts: Date
    public let model: String
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite5m: Int
    public let cacheWrite1h: Int
    public let cost: Double

    public init(key: String, ts: Date, model: String, input: Int, output: Int,
                cacheRead: Int, cacheWrite5m: Int, cacheWrite1h: Int, cost: Double) {
        self.key = key
        self.ts = ts
        self.model = model
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cost = cost
    }
}

public struct TokenTotals {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0
    public var cost = 0.0
    public var messages = 0

    public init() {}

    public mutating func add(_ e: UsageEvent) {
        input += e.input
        output += e.output
        cacheRead += e.cacheRead
        cacheWrite5m += e.cacheWrite5m
        cacheWrite1h += e.cacheWrite1h
        cost += e.cost
        messages += 1
    }

    public var totalTokens: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }
    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
}

public struct DayUsage: Identifiable {
    public let day: Date
    public var totals = TokenTotals()
    public var id: Date { day }

    public init(day: Date, totals: TokenTotals = TokenTotals()) {
        self.day = day
        self.totals = totals
    }
}

public struct ModelUsage: Identifiable {
    public let model: String
    public var totals = TokenTotals()
    public var id: String { model }

    public init(model: String, totals: TokenTotals = TokenTotals()) {
        self.model = model
        self.totals = totals
    }
}

public struct BlockInfo {
    public let start: Date
    public var lastActivity: Date
    public var totals = TokenTotals()
    public var end: Date { start.addingTimeInterval(5 * 3600) }

    public init(start: Date, lastActivity: Date, totals: TokenTotals = TokenTotals()) {
        self.start = start
        self.lastActivity = lastActivity
        self.totals = totals
    }
}

public struct UsageSnapshot {
    public var today = TokenTotals()
    public var last7 = TokenTotals()
    public var last30 = TokenTotals()
    public var days: [DayUsage] = []
    public var models: [ModelUsage] = []
    public var currentBlock: BlockInfo?
    public var maxBlockCost: Double = 0
    public var lastUpdated = Date()

    public init() {}
}

public struct PlanGauge: Identifiable {
    public let key: String
    public let label: String
    public let utilization: Double
    public let resetsAt: Date?
    public var id: String { key }

    public init(key: String, label: String, utilization: Double, resetsAt: Date?) {
        self.key = key
        self.label = label
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct ExtraUsage {
    public let utilization: Double?
    public let usedCredits: Double?
    public let monthlyLimit: Double?

    public init(utilization: Double?, usedCredits: Double?, monthlyLimit: Double?) {
        self.utilization = utilization
        self.usedCredits = usedCredits
        self.monthlyLimit = monthlyLimit
    }
}

public struct CreditsInfo {
    public let unlimited: Bool
    public let balance: String?

    public init(unlimited: Bool, balance: String?) {
        self.unlimited = unlimited
        self.balance = balance
    }
}

public struct SpendLimit {
    public let limitText: String
    public let usedText: String
    public let usedPercent: Double?
    public let resetsAt: Date?

    public init(limitText: String, usedText: String, usedPercent: Double?, resetsAt: Date?) {
        self.limitText = limitText
        self.usedText = usedText
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct PlanStatus {
    public var gauges: [PlanGauge] = []
    public var subscription: String?
    public var error: String?
    public var needsLogin = false
    public var accountEmail: String?
    public var accountName: String?
    public var extraUsage: ExtraUsage?
    public var credits: CreditsInfo?
    public var spendLimit: SpendLimit?
    public var limitReachedReason: String?

    public init(gauges: [PlanGauge] = [], subscription: String? = nil, error: String? = nil,
                needsLogin: Bool = false, accountEmail: String? = nil, accountName: String? = nil,
                extraUsage: ExtraUsage? = nil, credits: CreditsInfo? = nil,
                spendLimit: SpendLimit? = nil, limitReachedReason: String? = nil) {
        self.gauges = gauges
        self.subscription = subscription
        self.error = error
        self.needsLogin = needsLogin
        self.accountEmail = accountEmail
        self.accountName = accountName
        self.extraUsage = extraUsage
        self.credits = credits
        self.spendLimit = spendLimit
        self.limitReachedReason = limitReachedReason
    }

    public var hasExtras: Bool {
        extraUsage != nil || credits != nil || spendLimit != nil
    }
}

public enum ProviderKind: String, CaseIterable {
    case anthropic
    case openAI
    case openCode
    case deepSeek

    public var name: String {
        switch self {
        case .anthropic: return "Claude"
        case .openAI: return "OpenAI"
        case .openCode: return "OpenCode"
        case .deepSeek: return "DeepSeek"
        }
    }

    public var detail: String {
        switch self {
        case .anthropic: return "Claude Code"
        case .openAI: return "Codex CLI"
        case .openCode: return "opencode.db"
        case .deepSeek: return "API"
        }
    }

    // Providers whose token/cost breakdown comes from a local usage log.
    public var hasLocalUsage: Bool {
        switch self {
        case .anthropic, .openAI, .openCode: return true
        case .deepSeek: return false
        }
    }

    public var colorHex: String {
        switch self {
        case .anthropic: return "#D97757"
        case .openAI: return "#10A37F"
        case .openCode: return "#8B7CF6"
        case .deepSeek: return "#4D6BFE"
        }
    }
}

public struct ProviderData {
    public let kind: ProviderKind
    public var snapshot = UsageSnapshot()
    public var plan = PlanStatus()
    public var available = false

    public init(kind: ProviderKind, snapshot: UsageSnapshot = UsageSnapshot(),
                plan: PlanStatus = PlanStatus(), available: Bool = false) {
        self.kind = kind
        self.snapshot = snapshot
        self.plan = plan
        self.available = available
    }

    public var primaryGauge: PlanGauge? {
        let preferred = kind == .anthropic ? "five_hour" : "primary"
        return plan.gauges.first(where: { $0.key == preferred }) ?? plan.gauges.first
    }

    public var menuGauges: [PlanGauge] {
        let keys = kind == .anthropic ? ["five_hour", "seven_day"] : ["primary", "secondary"]
        var out: [PlanGauge] = []
        for key in keys {
            if let g = plan.gauges.first(where: { $0.key == key }) { out.append(g) }
        }
        if out.count < 2 {
            for g in plan.gauges where !out.contains(where: { $0.key == g.key }) {
                out.append(g)
                if out.count == 2 { break }
            }
        }
        return out
    }
}
