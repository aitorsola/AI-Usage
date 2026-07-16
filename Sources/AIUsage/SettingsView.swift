import SwiftUI
import AppKit
import ServiceManagement

enum SettingsKeys {
    static let limitDisplay = "limitDisplay"
    static let menuSource = "menuSource"
    static let menuSections = "menuSections"
}

enum MenuSectionID: String, CaseIterable {
    case claude
    case openai
    case week

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .week: return L.t("Últimos 7 días", "Last 7 days")
        }
    }
}

struct MenuSectionSetting: Identifiable {
    let id: MenuSectionID
    var visible: Bool
}

enum MenuSectionsConfig {
    static let storageDefault = "claude:1,openai:1,week:1"

    static func parse(_ raw: String) -> [MenuSectionSetting] {
        var items: [MenuSectionSetting] = []
        for part in raw.split(separator: ",") {
            let bits = part.split(separator: ":")
            guard let first = bits.first,
                  let id = MenuSectionID(rawValue: String(first)),
                  !items.contains(where: { $0.id == id })
            else { continue }
            let visible = bits.count > 1 ? bits[1] == "1" : true
            items.append(MenuSectionSetting(id: id, visible: visible))
        }
        for id in MenuSectionID.allCases where !items.contains(where: { $0.id == id }) {
            items.append(MenuSectionSetting(id: id, visible: true))
        }
        return items
    }

    static func serialize(_ items: [MenuSectionSetting]) -> String {
        items.map { "\($0.id.rawValue):\($0.visible ? "1" : "0")" }.joined(separator: ",")
    }
}

enum LimitDisplay: String, CaseIterable, Identifiable {
    case remaining
    case used
    var id: String { rawValue }
    var label: String {
        switch self {
        case .remaining: return L.t("Restante", "Remaining")
        case .used: return L.t("Consumido", "Used")
        }
    }
}

enum MenuSource: String, CaseIterable, Identifiable {
    case auto
    case anthropic
    case openAI
    case cost
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return L.t("Automático (Claude primero)", "Automatic (Claude first)")
        case .anthropic: return "Claude"
        case .openAI: return "OpenAI"
        case .cost: return L.t("Coste de hoy (total)", "Today's cost (total)")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKeys.limitDisplay) private var limitDisplay = LimitDisplay.remaining.rawValue
    @AppStorage(SettingsKeys.menuSource) private var menuSource = MenuSource.auto.rawValue
    @AppStorage(SettingsKeys.menuSections) private var menuSectionsRaw = MenuSectionsConfig.storageDefault

    var body: some View {
        Form {
            Section(L.t("Visualización", "Display")) {
                Picker(L.t("Mostrar límites como", "Show limits as"), selection: $limitDisplay) {
                    ForEach(LimitDisplay.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Picker(L.t("La barra de menús muestra", "Menu bar shows"), selection: $menuSource) {
                    ForEach(MenuSource.allCases) { source in
                        Text(source.label).tag(source.rawValue)
                    }
                }
                LaunchAtLoginToggle()
            }

            Section(L.t("Secciones del menú", "Menu sections")) {
                let sections = MenuSectionsConfig.parse(menuSectionsRaw)
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    HStack {
                        Toggle(section.id.title, isOn: Binding(
                            get: { section.visible },
                            set: { setSectionVisible(section.id, $0) }))
                        Spacer()
                        Button {
                            moveSection(section.id, delta: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button {
                            moveSection(section.id, delta: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == sections.count - 1)
                    }
                }
                Button(L.t("Restaurar orden por defecto", "Restore default order")) {
                    menuSectionsRaw = MenuSectionsConfig.storageDefault
                }
                .controlSize(.small)
            }

            Section("Claude (Anthropic)") {
                LabeledContent(L.t("Sesión", "Session"), value: anthropicSessionDescription)
                if let account = accountDescription(store.anthropic.plan) {
                    LabeledContent(L.t("Cuenta", "Account"), value: account)
                }
                HStack {
                    Button(L.t("Iniciar sesión con Claude…", "Sign in with Claude…")) {
                        openWindow(id: "login")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .tint(ProviderKind.anthropic.color)
                    if AnthropicTokenStore.load() != nil {
                        Button(L.t("Cerrar sesión propia", "Sign out"), role: .destructive) {
                            AnthropicTokenStore.delete()
                            store.refresh()
                        }
                    }
                }
                Text(L.t("La sesión se guarda en un ítem propio del llavero. La app no lee las credenciales de Claude Code, así que macOS no pide permisos de acceso.", "The session is stored in the app's own keychain item. The app never reads Claude Code's credentials, so macOS won't ask for keychain access."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI (Codex CLI)") {
                LabeledContent(L.t("Sesión", "Session"), value: openAISessionDescription)
                if let account = accountDescription(store.openAI.plan) {
                    LabeledContent(L.t("Cuenta", "Account"), value: account)
                }
                LabeledContent(L.t("Datos locales", "Local data"), value: openAIDescription)
                HStack {
                    Button(L.t("Iniciar sesión con OpenAI…", "Sign in with OpenAI…")) {
                        openWindow(id: "login-openai")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .tint(ProviderKind.openAI.color)
                    if OpenAITokenStore.load() != nil {
                        Button(L.t("Cerrar sesión propia", "Sign out"), role: .destructive) {
                            OpenAITokenStore.delete()
                            store.refresh()
                        }
                    }
                }
                Text(L.t("Los tokens salen de las sesiones locales de Codex CLI (~/.codex/sessions). Los límites del plan se consultan en vivo a chatgpt.com con tu sesión de OpenAI.", "Token counts come from local Codex CLI sessions (~/.codex/sessions). Plan limits are fetched live from chatgpt.com using your OpenAI session."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { ActivationPolicy.windowAppeared() }
        .onDisappear { ActivationPolicy.windowClosed() }
    }

    private func accountDescription(_ plan: PlanStatus) -> String? {
        var parts: [String] = []
        if let email = plan.accountEmail { parts.append(email) }
        if let name = plan.accountName, !parts.contains(name) { parts.append(name) }
        if let sub = plan.subscription { parts.append("plan \(sub.capitalized)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func setSectionVisible(_ id: MenuSectionID, _ visible: Bool) {
        var items = MenuSectionsConfig.parse(menuSectionsRaw)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].visible = visible
        menuSectionsRaw = MenuSectionsConfig.serialize(items)
    }

    private func moveSection(_ id: MenuSectionID, delta: Int) {
        var items = MenuSectionsConfig.parse(menuSectionsRaw)
        guard let i = items.firstIndex(where: { $0.id == id }),
              (0..<items.count).contains(i + delta) else { return }
        items.swapAt(i, i + delta)
        menuSectionsRaw = MenuSectionsConfig.serialize(items)
    }

    private var anthropicSessionDescription: String {
        if let own = AnthropicTokenStore.load() {
            if let exp = own.expiresAt {
                return exp > Date()
                    ? String(format: L.t("propia de la app (caduca %@)", "app's own (expires %@)"), Formatters.time(exp))
                    : L.t("propia de la app (renovación automática)", "app's own (auto-refresh)")
            }
            return L.t("propia de la app", "app's own")
        }
        return L.t("sin sesión", "no session")
    }

    private var openAISessionDescription: String {
        if let own = OpenAITokenStore.load() {
            if let exp = own.expiresAt, exp > Date() {
                return String(format: L.t("propia de la app (caduca %@)", "app's own (expires %@)"), Formatters.time(exp))
            }
            return L.t("propia de la app (renovación automática)", "app's own (auto-refresh)")
        }
        if CodexAuthFile.load() != nil {
            return L.t("auth.json de Codex CLI", "Codex CLI auth.json")
        }
        return L.t("sin sesión", "no session")
    }

    private var openAIDescription: String {
        if !store.openAI.available && store.openAI.plan.error?.contains("no encontrado") == true {
            return L.t("Codex CLI no encontrado", "Codex CLI not found")
        }
        let msgs = store.openAI.snapshot.last30.messages
        var parts = [L.t("Codex CLI detectado", "Codex CLI detected")]
        if msgs > 0 { parts.append(String(format: L.t("%d turnos en 30 días", "%d turns in 30 days"), msgs)) }
        if let plan = store.openAI.plan.subscription { parts.append("plan \(plan)") }
        return parts.joined(separator: " · ")
    }
}
