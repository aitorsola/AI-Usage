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
    case openCode
    case deepSeek
    case week

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .openCode: return "OpenCode"
        case .deepSeek: return "DeepSeek"
        case .week: return L.t("last_7_days")
        }
    }
}

struct MenuSectionSetting: Identifiable {
    let id: MenuSectionID
    var visible: Bool
}

enum MenuSectionsConfig {
    static let storageDefault = "claude:1,openai:1,openCode:1,deepSeek:1,week:1"

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
        case .remaining: return L.t("remaining")
        case .used: return L.t("used")
        }
    }
}

enum MenuSource: String, CaseIterable, Identifiable {
    case auto
    case anthropic
    case openAI
    case openCode
    case deepSeek
    case cost
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return L.t("automatic_claude_first")
        case .anthropic: return "Claude"
        case .openAI: return "OpenAI"
        case .openCode: return "OpenCode"
        case .deepSeek: return "DeepSeek"
        case .cost: return L.t("todays_cost_total")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKeys.limitDisplay) private var limitDisplay = LimitDisplay.remaining.rawValue
    @AppStorage(SettingsKeys.menuSource) private var menuSource = MenuSource.auto.rawValue
    @AppStorage(SettingsKeys.menuSections) private var menuSectionsRaw = MenuSectionsConfig.storageDefault
    @State private var deepSeekKeyInput = ""

    // Cap the window so it never extends behind the Dock; the Form scrolls beyond this.
    static var maxContentHeight: CGFloat {
        max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
    }

    var body: some View {
        Form {
            Section(L.t("display")) {
                Picker(L.t("show_limits_as"), selection: $limitDisplay) {
                    ForEach(LimitDisplay.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Picker(L.t("menu_bar_shows"), selection: $menuSource) {
                    ForEach(MenuSource.allCases) { source in
                        Text(source.label).tag(source.rawValue)
                    }
                }
                LaunchAtLoginToggle()
            }

            Section(L.t("menu_sections")) {
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
                Button(L.t("restore_default_order")) {
                    menuSectionsRaw = MenuSectionsConfig.storageDefault
                }
                .controlSize(.small)
            }

            Section("Claude (Anthropic)") {
                LabeledContent(L.t("session"), value: anthropicSessionDescription)
                if let account = accountDescription(store.anthropic.plan) {
                    LabeledContent(L.t("account"), value: account)
                }
                HStack {
                    if AnthropicTokenStore.load() == nil {
                        Button(L.t("sign_in_with_claude")) {
                            openWindow(id: "login")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .tint(ProviderKind.anthropic.color)
                    } else {
                        Button(L.t("sign_out"), role: .destructive) {
                            AnthropicTokenStore.delete()
                            store.refresh()
                        }
                    }
                }
                Text(L.t("the_session_is_stored_in_the"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI (Codex CLI)") {
                LabeledContent(L.t("session"), value: openAISessionDescription)
                if let account = accountDescription(store.openAI.plan) {
                    LabeledContent(L.t("account"), value: account)
                }
                LabeledContent(L.t("local_data"), value: openAIDescription)
                HStack {
                    if OpenAITokenStore.load() == nil {
                        Button(L.t("sign_in_with_openai")) {
                            openWindow(id: "login-openai")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .tint(ProviderKind.openAI.color)
                    } else {
                        Button(L.t("sign_out"), role: .destructive) {
                            OpenAITokenStore.delete()
                            store.refresh()
                        }
                    }
                }
                Text(L.t("token_counts_come_from_local_codex"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenCode") {
                LabeledContent(L.t("local_data"), value: openCodeDescription)
                Text(L.t("opencode_caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("DeepSeek") {
                let keyPresent = DeepSeekKeyStore.load() != nil
                let keyInvalid = keyPresent && store.hasLoaded && store.deepSeek.plan.needsLogin
                LabeledContent(L.t("session"), value: deepSeekSessionDescription)
                    .foregroundStyle(keyInvalid ? Color.secondary : Color.primary)
                if let balance = deepSeekBalance {
                    LabeledContent(L.t("balance"), value: balance)
                }
                if !keyPresent || keyInvalid {
                    SecureField(L.t("paste_api_key"), text: $deepSeekKeyInput)
                    Button(L.t("save")) {
                        DeepSeekKeyStore.save(deepSeekKeyInput)
                        deepSeekKeyInput = ""
                        store.refresh()
                    }
                    .tint(ProviderKind.deepSeek.color)
                    .disabled(deepSeekKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if keyPresent {
                    Button(L.t("sign_out"), role: .destructive) {
                        DeepSeekKeyStore.delete()
                        store.refresh()
                    }
                }
                Text(L.t("deepseek_caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: Self.maxContentHeight)
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
        AnthropicTokenStore.load() != nil
            ? L.t("active")
            : L.t("not_signed_in")
    }

    private var openAISessionDescription: String {
        (OpenAITokenStore.load() != nil || CodexAuthFile.load() != nil)
            ? L.t("active")
            : L.t("not_signed_in")
    }

    private var openAIDescription: String {
        if !store.openAI.available && store.openAI.plan.error?.contains("no encontrado") == true {
            return L.t("codex_cli_not_found")
        }
        let msgs = store.openAI.snapshot.last30.messages
        var parts = [L.t("codex_cli_detected")]
        if msgs > 0 { parts.append(String(format: L.t("turns_in_30_days"), msgs)) }
        if let plan = store.openAI.plan.subscription { parts.append("plan \(plan)") }
        return parts.joined(separator: " · ")
    }

    private var openCodeDescription: String {
        guard store.openCode.available else { return L.t("no_opencode_data") }
        let snap = store.openCode.snapshot
        return "\(Formatters.tokens(snap.last30.totalTokens)) tokens · \(Formatters.cost(snap.last30.cost))"
    }

    private var deepSeekBalance: String? {
        guard let balance = store.deepSeek.plan.credits?.balance else { return nil }
        return Formatters.money(balance)
    }

    private var deepSeekSessionDescription: String {
        guard DeepSeekKeyStore.load() != nil else { return L.t("not_signed_in") }
        if store.hasLoaded && store.deepSeek.plan.needsLogin { return L.t("invalid_api_key") }
        return L.t("active")
    }
}
