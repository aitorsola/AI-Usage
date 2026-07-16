import Foundation
import Combine

final class UsageStore: ObservableObject {
    @Published var anthropic = ProviderData(kind: .anthropic)
    @Published var openAI = ProviderData(kind: .openAI)
    @Published var openCode = ProviderData(kind: .openCode)
    @Published var deepSeek = ProviderData(kind: .deepSeek)
    @Published var isRefreshing = false
    @Published var hasLoaded = false
    @Published var lastUpdated = Date()

    private let claudeParser = UsageParser()
    private let codexParser = CodexParser()
    private let openCodeParser = OpenCodeParser()
    private let queue = DispatchQueue(label: "aiusage.refresh", qos: .utility)
    private var timer: Timer?
    private var refreshing = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.main.async {
            guard !self.refreshing else { return }
            self.refreshing = true
            self.isRefreshing = true
            self.queue.async {
                let cutoff = Calendar.current.date(byAdding: .day, value: -35, to: Date())!

                let claudeEvents = self.claudeParser.collectEvents(since: cutoff)
                let claudeSnap = Aggregator.snapshot(from: claudeEvents)

                let codex = self.codexParser.collect(since: cutoff)
                let codexSnap = Aggregator.snapshot(from: codex.events)

                let opencode = self.openCodeParser.collect(since: cutoff)
                let opencodeSnap = Aggregator.snapshot(from: opencode.events)

                let group = DispatchGroup()
                var claudePlan = PlanStatus()
                var openAILive = PlanStatus()
                var deepSeekPlan = PlanStatus()
                group.enter()
                PlanFetcher.fetch { claudePlan = $0; group.leave() }
                group.enter()
                OpenAIUsageFetcher.fetch { openAILive = $0; group.leave() }
                group.enter()
                DeepSeekFetcher.fetch { deepSeekPlan = $0; group.leave() }

                group.notify(queue: .main) {
                    var openAIPlan = openAILive
                    if openAIPlan.gauges.isEmpty && openAIPlan.error == nil {
                        openAIPlan.error = L.t("no_limit_data")
                    }
                    let openAIAvailable = codex.installed
                        || !openAIPlan.gauges.isEmpty
                        || codexSnap.last30.messages > 0

                    self.anthropic = ProviderData(kind: .anthropic, snapshot: claudeSnap,
                                                  plan: claudePlan, available: true)
                    self.openAI = ProviderData(kind: .openAI, snapshot: codexSnap,
                                               plan: openAIPlan, available: openAIAvailable)
                    self.openCode = ProviderData(kind: .openCode, snapshot: opencodeSnap,
                                                 plan: PlanStatus(),
                                                 available: opencode.installed && opencodeSnap.last30.messages > 0)
                    self.deepSeek = ProviderData(kind: .deepSeek, snapshot: UsageSnapshot(),
                                                 plan: deepSeekPlan,
                                                 available: !deepSeekPlan.needsLogin)
                    self.lastUpdated = Date()
                    self.hasLoaded = true
                    self.isRefreshing = false
                    self.refreshing = false
                }
            }
        }
    }

    var combinedDays: [DayUsage] {
        let a = anthropic.snapshot.days
        let b = openAI.snapshot.days
        guard !b.isEmpty, b.contains(where: { $0.totals.cost > 0 }), a.count == b.count else {
            return a
        }
        return zip(a, b).map { d1, d2 in
            var d = DayUsage(day: d1.day)
            d.totals = d1.totals
            d.totals.absorb(d2.totals)
            return d
        }
    }

    var combinedTodayCost: Double {
        anthropic.snapshot.today.cost + openAI.snapshot.today.cost
    }
}

extension TokenTotals {
    mutating func absorb(_ other: TokenTotals) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite5m += other.cacheWrite5m
        cacheWrite1h += other.cacheWrite1h
        cost += other.cost
        messages += other.messages
    }
}
