import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedProvider = ProviderKind.anthropic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                providerPicker
                providerPage(current)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 660, idealWidth: 720, minHeight: 560, idealHeight: 680)
        .onAppear { ActivationPolicy.windowAppeared() }
        .onDisappear { ActivationPolicy.windowClosed() }
    }

    private var current: ProviderData {
        selectedProvider == .anthropic ? store.anthropic : store.openAI
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "asterisk")
                .font(.title2)
                .foregroundStyle(current.kind.color)
            Text("AI Usage")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Text(String(format: L.t("Actualizado a las %@", "Updated at %@"), Formatters.time(store.lastUpdated)))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L.t("Actualizar ahora", "Refresh now"))
            }
        }
    }

    private var providerPicker: some View {
        HStack {
            Picker("", selection: $selectedProvider) {
                ForEach(ProviderKind.allCases, id: \.self) { kind in
                    Text(kind.name).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            if let sub = current.plan.subscription {
                Text("Plan \(sub.capitalized)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(current.kind.color.opacity(0.18)))
            }
            Text(current.kind.detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    @ViewBuilder
    private func providerPage(_ provider: ProviderData) -> some View {
        if provider.kind == .openAI && !provider.available && !provider.plan.needsLogin {
            section("OpenAI") {
                Text(provider.plan.error ?? L.t("No se han encontrado sesiones de Codex CLI en ~/.codex.", "No Codex CLI sessions found in ~/.codex."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            statTiles(provider)
            planSection(provider)
            dailySection(provider)
            modelSection(provider)
        }
    }

    private func loginButton(_ provider: ProviderData) -> some View {
        Button {
            openWindow(id: provider.kind == .anthropic ? "login" : "login-openai")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label(String(format: L.t("Iniciar sesión con %@", "Sign in with %@"), provider.kind.name),
                  systemImage: "person.crop.circle.badge.plus")
        }
        .tint(provider.kind.color)
    }

    private func statTiles(_ provider: ProviderData) -> some View {
        let snap = provider.snapshot
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatTile(title: L.t("Hoy", "Today"),
                     value: Formatters.cost(snap.today.cost),
                     detail: "\(snap.today.messages) \(L.t("mensajes", "messages")) · \(Formatters.tokens(snap.today.totalTokens)) tokens")
            if let block = snap.currentBlock {
                StatTile(title: L.t("Bloque actual (5 h)", "Current block (5 h)"),
                         value: Formatters.cost(block.totals.cost),
                         detail: String(format: L.t("termina a las %@", "ends at %@"), Formatters.time(block.end)))
            } else {
                StatTile(title: L.t("Bloque actual (5 h)", "Current block (5 h)"),
                         value: "—",
                         detail: L.t("sin actividad reciente", "no recent activity"))
            }
            StatTile(title: L.t("Últimos 7 días", "Last 7 days"),
                     value: Formatters.cost(snap.last7.cost),
                     detail: "\(Formatters.tokens(snap.last7.totalTokens)) tokens")
            StatTile(title: L.t("Últimos 30 días", "Last 30 days"),
                     value: Formatters.cost(snap.last30.cost),
                     detail: "\(Formatters.tokens(snap.last30.totalTokens)) tokens")
        }
    }

    @ViewBuilder
    private func planSection(_ provider: ProviderData) -> some View {
        if provider.plan.needsLogin {
            section(L.t("Límites del plan", "Plan limits")) {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = provider.plan.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    loginButton(provider)
                }
            }
        } else if !provider.plan.gauges.isEmpty || provider.plan.hasExtras {
            section(L.t("Límites del plan", "Plan limits")) {
                VStack(alignment: .leading, spacing: 14) {
                    if let reason = provider.plan.limitReachedReason {
                        LimitBanner(reason: reason)
                    }
                    if !provider.plan.gauges.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 2),
                                  alignment: .leading, spacing: 14) {
                            ForEach(provider.plan.gauges) { gauge in
                                GaugeRow(gauge: gauge, tint: provider.kind.color)
                            }
                        }
                    }
                    if provider.plan.hasExtras {
                        PlanExtrasView(plan: provider.plan, tint: provider.kind.color)
                            .frame(maxWidth: 360)
                    }
                }
            }
        } else if let error = provider.plan.error {
            section(L.t("Límites del plan", "Plan limits")) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dailySection(_ provider: ProviderData) -> some View {
        let days = Array(provider.snapshot.days.suffix(14)).reversed()
        let maxCost = provider.snapshot.days.suffix(14).map(\.totals.cost).max() ?? 0
        return section(L.t("Últimos 14 días", "Last 14 days")) {
            VStack(spacing: 6) {
                ForEach(Array(days)) { day in
                    DailyRow(day: day, maxCost: maxCost, tint: provider.kind.color)
                }
            }
        }
    }

    @ViewBuilder
    private func modelSection(_ provider: ProviderData) -> some View {
        if !provider.snapshot.models.isEmpty {
            section(L.t("Por modelo (últimos 30 días)", "By model (last 30 days)")) {
                VStack(spacing: 4) {
                    modelHeaderRow
                    ForEach(provider.snapshot.models) { model in
                        modelRow(model)
                    }
                }
            }
        }
    }

    private var modelHeaderRow: some View {
        HStack {
            Text(L.t("Modelo", "Model")).frame(width: 130, alignment: .leading)
            Spacer()
            Text(L.t("Mensajes", "Messages")).frame(width: 70, alignment: .trailing)
            Text(L.t("Entrada", "Input")).frame(width: 70, alignment: .trailing)
            Text(L.t("Salida", "Output")).frame(width: 70, alignment: .trailing)
            Text(L.t("Caché", "Cache")).frame(width: 70, alignment: .trailing)
            Text(L.t("Coste", "Cost")).frame(width: 70, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func modelRow(_ model: ModelUsage) -> some View {
        HStack {
            Text(Formatters.modelName(model.model))
                .font(.caption)
                .frame(width: 130, alignment: .leading)
                .help(model.model)
            Spacer()
            Group {
                Text("\(model.totals.messages)").frame(width: 70, alignment: .trailing)
                Text(Formatters.tokens(model.totals.input)).frame(width: 70, alignment: .trailing)
                Text(Formatters.tokens(model.totals.output)).frame(width: 70, alignment: .trailing)
                Text(Formatters.tokens(model.totals.cacheRead + model.totals.cacheWrite))
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            Text(Formatters.cost(model.totals.cost))
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
