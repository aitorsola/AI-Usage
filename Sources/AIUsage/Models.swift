import Foundation

struct UsageEvent {
    let key: String
    let ts: Date
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite5m: Int
    let cacheWrite1h: Int
    let cost: Double
}

struct TokenTotals {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cost = 0.0
    var messages = 0

    mutating func add(_ e: UsageEvent) {
        input += e.input
        output += e.output
        cacheRead += e.cacheRead
        cacheWrite5m += e.cacheWrite5m
        cacheWrite1h += e.cacheWrite1h
        cost += e.cost
        messages += 1
    }

    var totalTokens: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }
    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
}

struct DayUsage: Identifiable {
    let day: Date
    var totals = TokenTotals()
    var id: Date { day }
}

struct ModelUsage: Identifiable {
    let model: String
    var totals = TokenTotals()
    var id: String { model }
}

struct BlockInfo {
    let start: Date
    var lastActivity: Date
    var totals = TokenTotals()
    var end: Date { start.addingTimeInterval(5 * 3600) }
}

struct UsageSnapshot {
    var today = TokenTotals()
    var last7 = TokenTotals()
    var last30 = TokenTotals()
    var days: [DayUsage] = []
    var models: [ModelUsage] = []
    var currentBlock: BlockInfo?
    var maxBlockCost: Double = 0
    var lastUpdated = Date()
}

struct PlanGauge: Identifiable {
    let key: String
    let label: String
    let utilization: Double
    let resetsAt: Date?
    var id: String { key }
}

struct ExtraUsage {
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?
}

struct CreditsInfo {
    let unlimited: Bool
    let balance: String?
}

struct SpendLimit {
    let limitText: String
    let usedText: String
    let usedPercent: Double?
    let resetsAt: Date?
}

struct PlanStatus {
    var gauges: [PlanGauge] = []
    var subscription: String?
    var error: String?
    var needsLogin = false
    var accountEmail: String?
    var accountName: String?
    var extraUsage: ExtraUsage?
    var credits: CreditsInfo?
    var spendLimit: SpendLimit?
    var limitReachedReason: String?

    var hasExtras: Bool {
        extraUsage != nil || credits != nil || spendLimit != nil
    }
}

enum ProviderKind: String, CaseIterable {
    case anthropic
    case openAI
    case openCode
    case deepSeek

    var name: String {
        switch self {
        case .anthropic: return "Claude"
        case .openAI: return "OpenAI"
        case .openCode: return "OpenCode"
        case .deepSeek: return "DeepSeek"
        }
    }

    var detail: String {
        switch self {
        case .anthropic: return "Claude Code"
        case .openAI: return "Codex CLI"
        case .openCode: return "opencode.db"
        case .deepSeek: return "API"
        }
    }

    // Providers whose token/cost breakdown comes from a local usage log.
    var hasLocalUsage: Bool {
        switch self {
        case .anthropic, .openAI, .openCode: return true
        case .deepSeek: return false
        }
    }
}

struct ProviderData {
    let kind: ProviderKind
    var snapshot = UsageSnapshot()
    var plan = PlanStatus()
    var available = false

    var primaryGauge: PlanGauge? {
        let preferred = kind == .anthropic ? "five_hour" : "primary"
        return plan.gauges.first(where: { $0.key == preferred }) ?? plan.gauges.first
    }

    var menuGauges: [PlanGauge] {
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
