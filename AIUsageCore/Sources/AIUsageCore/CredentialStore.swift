//
//  CredentialStore.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation
import Security

// Central storage for every provider token/key, readable by the app AND its
// widget/complication extension on every platform — that is what lets each
// of them refresh on its own instead of waiting for the app to be opened.
//
// iOS/watchOS: the data-protection keychain, shared through the access group
// granted by the keychain-access-groups entitlement (implicit — the
// entitlement's first group, identical across app and extension).
//
// macOS: a 0600 file in the App Group container. keychain-access-groups is a
// restricted entitlement there (it needs an embedded provisioning profile the
// notarized Developer ID flow does not carry), so a keychain item would be
// invisible to the sandboxed widget and the widget could never fetch without
// the menu bar app running. The container is user-only, like ~/.codex/auth.json
// or ~/.claude/.credentials.json. Items found in the legacy keychain item are
// migrated over once.
enum CredentialStore {
    static func load(service: String) -> Data? {
        #if os(macOS)
        if let data = try? Data(contentsOf: fileURL(service)) { return data }
        // One-time migration from the keychain item earlier builds used. Only
        // the app looks there: from the sandboxed widget (a different code
        // signature) the lookup would raise a keychain prompt with no UI
        // behind it.
        guard !isExtension, let legacy = Keychain.load(service: service) else { return nil }
        if save(legacy, service: service) { Keychain.delete(service: service) }
        return legacy
        #else
        return Keychain.load(service: service)
        #endif
    }

    @discardableResult
    static func save(_ data: Data, service: String) -> Bool {
        #if os(macOS)
        let url = fileURL(service)
        let dir = url.deletingLastPathComponent()
        // A cleaner utility can delete the whole group container while the
        // app runs; recreate rather than assume it exists.
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
        #else
        return Keychain.save(data, service: service) == errSecSuccess
        #endif
    }

    static func delete(service: String) {
        #if os(macOS)
        try? FileManager.default.removeItem(at: fileURL(service))
        if !isExtension { Keychain.delete(service: service) }
        #else
        Keychain.delete(service: service)
        #endif
    }

    #if os(macOS)
    private static let isExtension = Bundle.main.bundleURL.pathExtension == "appex"

    private static func fileURL(_ service: String) -> URL {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AI Usage", isDirectory: true)
        let safe = String(service.map { ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return base.appendingPathComponent("credentials", isDirectory: true)
            .appendingPathComponent("\(safe).json")
    }
    #endif
}

private enum Keychain {
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
