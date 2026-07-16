//
//  DeepSeekAuth.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import Security

public enum DeepSeekKeyStore {
    static let service = "AI Usage-deepseek-key"

    public static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    public static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        delete()
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecValueData as String: data,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum DeepSeekFetcher {
    public static func fetch(completion: @escaping (PlanStatus) -> Void) {
        guard let key = DeepSeekKeyStore.load() else {
            completion(PlanStatus(needsLogin: true))
            return
        }
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            completion(PlanStatus(error: L.t("invalid_response")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                var plan = PlanStatus()
                plan.needsLogin = true
                plan.error = L.t("invalid_api_key")
                completion(plan)
                return
            }
            guard let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(PlanStatus(error: L.t("invalid_response")))
                return
            }
            let available = (obj["is_available"] as? Bool) ?? false
            let infos = (obj["balance_infos"] as? [[String: Any]]) ?? []
            let info = infos.first { ($0["currency"] as? String) == "USD" } ?? infos.first

            var plan = PlanStatus()
            plan.subscription = "API"
            if let info {
                let currency = (info["currency"] as? String) ?? "USD"
                let total = (info["total_balance"] as? String) ?? "0"
                plan.credits = CreditsInfo(unlimited: false, balance: Self.display(total, currency))
            }
            if !available {
                plan.limitReachedReason = L.t("balance_depleted")
            }
            completion(plan)
        }.resume()
    }

    private static func display(_ amount: String, _ currency: String) -> String {
        if currency == "USD" { return amount }            // formatted as $ by Formatters.money
        let value = Double(amount).map { String(format: "%.2f", $0) } ?? amount
        return "\(currency) \(value)"
    }
}
