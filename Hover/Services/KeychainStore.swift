//
//  KeychainStore.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Provides a small typed wrapper around SecItem APIs for storing API secrets.
//

import Foundation
import Security

final class KeychainStore {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "dev.hover.Hover") {
        self.service = service
    }

    func readString(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.unexpectedData
            }

            guard let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidStringData
            }

            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    func saveString(_ value: String, account: String) throws {
        guard !value.isEmpty else {
            try deleteString(account: account)
            return
        }

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidStringData
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(updateStatus)
        }

        var addQuery = baseQuery(account: account)
        attributes.forEach { key, value in
            addQuery[key] = value
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    func deleteString(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

enum KeychainError: LocalizedError {
    case invalidStringData
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStringData:
            "The API key could not be encoded for Keychain storage."
        case .unexpectedData:
            "The Keychain returned an unexpected value for the API key."
        case .unhandledStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}
