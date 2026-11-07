//
//  SharedStorage.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import Foundation
import Security

// MARK: - App Notifications

nonisolated extension Notification.Name {
    static let authStateDidChange = Notification.Name("com.workshop.expensetracker.authStateDidChange")
    static let expensesDidChange = Notification.Name("com.workshop.expensetracker.expensesDidChange")
}

// MARK: - SharedStorageError

enum SharedStorageError: LocalizedError, Sendable {
    case encodingFailed
    case decodingFailed
    case keychainError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for shared storage."
        case .decodingFailed:
            return "Failed to decode data from shared storage."
        case .keychainError(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error (\(status)): \(message)"
            }
            return "Keychain operation failed with status: \(status)"
        }
    }
}

// MARK: - SharedStorage

final class SharedStorage: @unchecked Sendable {

    // MARK: Singleton & Constants

    static let shared = SharedStorage()

    static let appGroupSuiteName = "group.com.workshop.expensetracker"

    private enum Keys {
        static let keychainService = "com.workshop.expensetracker.auth"
        static let bearerTokenAccount = "bearer_token"
        static let fallbackTokenDefaultsKey = "com.workshop.expensetracker.fallback.bearer_token"
        static let cachedSummaryPrefix = "com.workshop.expensetracker.cached_summary"
        static let latestSummaryKey = "com.workshop.expensetracker.cached_summary.latest"
        static let lastUpdatedKey = "com.workshop.expensetracker.cached_summary.last_updated"
    }

    // MARK: Properties

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: Initialization

    private init() {
        self.userDefaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard

        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        self.encoder = jsonEncoder

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        self.decoder = jsonDecoder
    }

    // MARK: - Bearer Token Management (Shared Keychain + Simulator Fallback)

    /// Thread-safe convenience property for accessing or updating the Bearer token.
    var token: String? {
        get { getToken() }
        set {
            if let newValue {
                saveToken(newValue)
            } else {
                deleteToken()
            }
        }
    }

    /// Indicates whether a non-empty Bearer token is currently stored.
    var isAuthenticated: Bool {
        guard let currentToken = getToken() else { return false }
        return !currentToken.isEmpty
    }

    /// Saves the Bearer token to the Shared Keychain, falling back to standard Keychain
    /// or App Group `UserDefaults` on the Simulator if shared entitlements are unavailable.
    @discardableResult
    func saveToken(_ token: String) -> Bool {
        lock.lock()
        let result: Bool
        if let data = token.data(using: .utf8) {
            #if targetEnvironment(simulator)
            if upsertKeychainItem(data: data, useAccessGroup: false) {
                userDefaults.removeObject(forKey: Keys.fallbackTokenDefaultsKey)
                result = true
            } else {
                userDefaults.set(token, forKey: Keys.fallbackTokenDefaultsKey)
                result = true
            }
            #else
            if upsertKeychainItem(data: data, useAccessGroup: true) {
                result = true
            } else if upsertKeychainItem(data: data, useAccessGroup: false) {
                result = true
            } else {
                userDefaults.set(token, forKey: Keys.fallbackTokenDefaultsKey)
                result = true
            }
            #endif
        } else {
            result = false
        }
        lock.unlock()

        if result {
            NotificationCenter.default.post(name: .authStateDidChange, object: nil)
        }
        return result
    }

    /// Retrieves the Bearer token from the Shared Keychain (or Simulator fallback).
    func getToken() -> String? {
        lock.lock()
        defer { lock.unlock() }

        #if targetEnvironment(simulator)
        if let data = readKeychainItem(useAccessGroup: false),
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        return userDefaults.string(forKey: Keys.fallbackTokenDefaultsKey)
        #else
        if let data = readKeychainItem(useAccessGroup: true),
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        if let data = readKeychainItem(useAccessGroup: false),
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        return userDefaults.string(forKey: Keys.fallbackTokenDefaultsKey)
        #endif
    }

    /// Deletes the Bearer token from Keychain and any fallback storage.
    @discardableResult
    func deleteToken() -> Bool {
        lock.lock()
        let removedShared = deleteKeychainItem(useAccessGroup: true)
        let removedLocal = deleteKeychainItem(useAccessGroup: false)
        userDefaults.removeObject(forKey: Keys.fallbackTokenDefaultsKey)
        lock.unlock()

        NotificationCenter.default.post(name: .authStateDidChange, object: nil)
        return removedShared || removedLocal
    }

    // MARK: - ExpenseSummary Offline Caching (App Group UserDefaults)

    /// Saves an `ExpenseSummary` to the App Group `UserDefaults` both as the latest summary
    /// and keyed by its period (`summary.period`), enabling offline Widget access.
    func saveSummary(_ summary: ExpenseSummary) {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? encoder.encode(summary) else { return }
        let periodKey = summaryKey(forPeriod: summary.period)
        userDefaults.set(data, forKey: periodKey)
        userDefaults.set(data, forKey: Keys.latestSummaryKey)
        userDefaults.set(Date.now, forKey: Keys.lastUpdatedKey)
    }

    /// Loads the cached `ExpenseSummary` for a specific period, or returns the most recently cached summary if `period` is nil.
    func getSummary(forPeriod period: String? = nil) -> ExpenseSummary? {
        lock.lock()
        defer { lock.unlock() }

        if let period {
            let key = summaryKey(forPeriod: period)
            if let data = userDefaults.data(forKey: key),
               let summary = try? decoder.decode(ExpenseSummary.self, from: data) {
                return summary
            }
        }

        guard let latestData = userDefaults.data(forKey: Keys.latestSummaryKey) else {
            return nil
        }
        return try? decoder.decode(ExpenseSummary.self, from: latestData)
    }

    /// Returns the timestamp when the cached `ExpenseSummary` was last updated.
    var lastSummaryUpdateDate: Date? {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.object(forKey: Keys.lastUpdatedKey) as? Date
    }

    /// Clears cached `ExpenseSummary` records from the App Group `UserDefaults`.
    func clearSummaries(periods: [String] = ["day", "week", "month", "year"]) {
        lock.lock()
        defer { lock.unlock() }

        userDefaults.removeObject(forKey: Keys.latestSummaryKey)
        userDefaults.removeObject(forKey: Keys.lastUpdatedKey)
        for period in periods {
            userDefaults.removeObject(forKey: summaryKey(forPeriod: period))
        }
    }

    /// Clears all authentication tokens and cached widget summaries.
    func clearAll() {
        _ = deleteToken()
        clearSummaries()
    }

    // MARK: - Private Keychain Helpers

    private func baseKeychainQuery(useAccessGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.bearerTokenAccount
        ]
        if useAccessGroup {
            query[kSecAttrAccessGroup as String] = Self.appGroupSuiteName
        }
        return query
    }

    private func upsertKeychainItem(data: Data, useAccessGroup: Bool) -> Bool {
        let query = baseKeychainQuery(useAccessGroup: useAccessGroup)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    private func readKeychainItem(useAccessGroup: Bool) -> Data? {
        var query = baseKeychainQuery(useAccessGroup: useAccessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func deleteKeychainItem(useAccessGroup: Bool) -> Bool {
        let query = baseKeychainQuery(useAccessGroup: useAccessGroup)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func summaryKey(forPeriod period: String) -> String {
        "\(Keys.cachedSummaryPrefix).\(period.lowercased())"
    }
}
