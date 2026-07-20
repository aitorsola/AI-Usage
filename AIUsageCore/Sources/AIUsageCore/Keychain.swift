//
//  Keychain.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import Security

// Central keychain storage for every provider token/key.
//
// On iOS/watchOS it uses the data-protection keychain and the access group
// granted by the keychain-access-groups entitlement (implicit — the
// entitlement's first group), so the widget/complication extensions share the
// tokens and can fetch on their own. The group is not named in code; it
// defaults to that first entitlement group, identical across app and extension.
//
// macOS keeps the plain login keychain: there, keychain-access-groups is a
// restricted entitlement that needs an embedded provisioning profile the
// notarized manual-signing flow doesn't carry, so the widget stays app-driven
// (fine — the menu bar app is always running).
enum Keychain {
    static func load(service: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        #if !os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    @discardableResult
    static func save(_ data: Data, service: String) -> OSStatus {
        delete(service: service)
        var attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecValueData as String: data,
        ]
        #if !os(macOS)
        attrs[kSecUseDataProtectionKeychain as String] = true
        // Readable during locked background refreshes (watch complication).
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        return SecItemAdd(attrs as CFDictionary, nil)
    }

    static func delete(service: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        #if !os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        SecItemDelete(query as CFDictionary)
    }
}
