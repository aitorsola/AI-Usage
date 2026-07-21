//
//  PlatformStatus.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Platform-wide health for a provider, from its public Statuspage.io feed
// (no auth). This reports incidents/degradation — NOT "peak hours", which no
// provider exposes — so a healthy badge means "no known incident", not "not
// busy". Only Claude and OpenAI publish a status page; the others return nil.
public enum PlatformHealth: String, Codable, Hashable {
    case operational, degraded, outage, maintenance

    // Maps the Statuspage indicator (none/minor/major/critical/maintenance).
    public init?(indicator: String) {
        switch indicator.lowercased() {
        case "none": self = .operational
        case "minor": self = .degraded
        case "major", "critical": self = .outage
        case "maintenance": self = .maintenance
        default: return nil
        }
    }

    public var colorHex: String {
        switch self {
        case .operational: return "#34C759"
        case .degraded: return "#FF9500"
        case .outage: return "#FF3B30"
        case .maintenance: return "#8E8E93"
        }
    }

    public var label: String {
        switch self {
        case .operational: return L.t("status_operational")
        case .degraded: return L.t("status_degraded")
        case .outage: return L.t("status_outage")
        case .maintenance: return L.t("status_maintenance")
        }
    }

    // An SF Symbol distinct from the provider's brand dot, so the status reads
    // as status (check vs. warning) rather than as another colored dot.
    public var iconName: String {
        switch self {
        case .operational: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .outage: return "xmark.octagon.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        }
    }

    public var isNoteworthy: Bool { self != .operational }
}

public extension ProviderKind {
    var statusURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://status.claude.com/api/v2/status.json")
        case .openAI: return URL(string: "https://status.openai.com/api/v2/status.json")
        case .openCode, .deepSeek: return nil   // no public status page
        }
    }
}

public enum StatusFetcher {
    public static func fetch(_ kind: ProviderKind, completion: @escaping (PlatformHealth?) -> Void) {
        guard let url = kind.statusURL else { completion(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let status = obj["status"] as? [String: Any],
                  let indicator = status["indicator"] as? String else {
                completion(nil)
                return
            }
            completion(PlatformHealth(indicator: indicator))
        }.resume()
    }

    public static func fetchAll(_ kinds: [ProviderKind],
                                completion: @escaping ([ProviderKind: PlatformHealth]) -> Void) {
        var out: [ProviderKind: PlatformHealth] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for kind in kinds {
            group.enter()
            fetch(kind) { health in
                if let health { lock.lock(); out[kind] = health; lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(out) }
    }
}
