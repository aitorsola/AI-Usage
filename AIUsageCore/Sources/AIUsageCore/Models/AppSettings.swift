//
//  AppSettings.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// User-facing settings model: storage keys and the enums that describe what the
// menu bar and dropdown can show. Kept in Models so Core can depend on it without
// reaching into the SettingsView layer.
public enum SettingsKeys {
    public static let limitDisplay = "limitDisplay"
    public static let menuSource = "menuSource"
    public static let menuSections = "menuSections"
}

public enum MenuSectionID: String, CaseIterable {
    case claude
    case openai
    case openCode
    case deepSeek
    case week

    public var title: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .openCode: return "OpenCode"
        case .deepSeek: return "DeepSeek"
        case .week: return L.t("last_7_days")
        }
    }
}

public struct MenuSectionSetting: Identifiable {
    public let id: MenuSectionID
    public var visible: Bool

    public init(id: MenuSectionID, visible: Bool) {
        self.id = id
        self.visible = visible
    }
}

public enum MenuSectionsConfig {
    public static let storageDefault = "claude:1,openai:1,openCode:1,deepSeek:1,week:1"

    public static func parse(_ raw: String) -> [MenuSectionSetting] {
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

    public static func serialize(_ items: [MenuSectionSetting]) -> String {
        items.map { "\($0.id.rawValue):\($0.visible ? "1" : "0")" }.joined(separator: ",")
    }
}

public enum LimitDisplay: String, CaseIterable, Identifiable {
    case remaining
    case used
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .remaining: return L.t("remaining")
        case .used: return L.t("used")
        }
    }
}

public enum MenuSource: String, CaseIterable, Identifiable {
    case auto
    case anthropic
    case openAI
    case openCode
    case deepSeek
    case cost
    public var id: String { rawValue }
    public var label: String {
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
