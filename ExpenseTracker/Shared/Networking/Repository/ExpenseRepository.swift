//
//  ExpenseRepository.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import Foundation
import WidgetKit

// MARK: - AppConfig

enum AppConfig {
    private static let useMockDataKey = "com.workshop.expensetracker.config.useMockData"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroupSuiteName) ?? .standard
    }

    /// Toggles offline mock data mode for conference demos.
    /// Persisted in the shared App Group `UserDefaults` so both the app and widget respect the flag.
    static var useMockData: Bool {
        get {
            defaults.bool(forKey: useMockDataKey)
        }
        set {
            defaults.set(newValue, forKey: useMockDataKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Returns the appropriate repository implementation based on `AppConfig.useMockData`.
    static func makeRepository() -> any ExpenseRepositoryProtocol {
        useMockData ? MockExpenseRepository.shared : LiveExpenseRepository.shared
    }
}

// MARK: - ExpenseRepositoryProtocol

protocol ExpenseRepositoryProtocol: Sendable {
    @discardableResult
    func login(email: String, password: String) async throws -> AuthResponse
    func register(email: String, password: String) async throws
    func logout()

    func fetchExpenses(from: Date?, to: Date?) async throws -> [Expense]

    @discardableResult
    func addExpense(
        amount: Double,
        currency: String,
        category: ExpenseCategory,
        note: String?,
        date: Date
    ) async throws -> Expense

    func deleteExpense(id: UUID) async throws

    func fetchSummary(
        period: String,
        days: Int?,
        topCategories: Int?
    ) async throws -> ExpenseSummary

    func seedDemo() async throws
}

// MARK: - Protocol Default Arguments & Convenience Methods

extension ExpenseRepositoryProtocol {
    func fetchExpenses(from: Date? = nil, to: Date? = nil) async throws -> [Expense] {
        try await fetchExpenses(from: from, to: to)
    }

    @discardableResult
    func addExpense(
        amount: Double,
        currency: String = "USD",
        category: ExpenseCategory,
        note: String? = nil,
        date: Date = .now
    ) async throws -> Expense {
        try await addExpense(
            amount: amount,
            currency: currency,
            category: category,
            note: note,
            date: date
        )
    }

    @discardableResult
    func addExpense(_ expense: Expense) async throws -> Expense {
        try await addExpense(
            amount: expense.amount,
            currency: expense.currency,
            category: expense.category,
            note: expense.note,
            date: expense.date
        )
    }

    func fetchSummary(
        period: String = "week",
        days: Int? = nil,
        topCategories: Int? = nil
    ) async throws -> ExpenseSummary {
        try await fetchSummary(period: period, days: days, topCategories: topCategories)
    }
}

// MARK: - LiveExpenseRepository

final class LiveExpenseRepository: ExpenseRepositoryProtocol, Sendable {

    static let shared = LiveExpenseRepository()

    private let apiClient: APIClient
    private let storage: SharedStorage

    init(
        apiClient: APIClient = .shared,
        storage: SharedStorage = .shared
    ) {
        self.apiClient = apiClient
        self.storage = storage
    }

    @discardableResult
    func login(email: String, password: String) async throws -> AuthResponse {
        let response = try await apiClient.login(email: email, password: password)
        storage.saveToken(response.accessToken)
        _ = try? await refreshAndCacheDefaultSummary()
        WidgetCenter.shared.reloadAllTimelines()
        return response
    }

    func register(email: String, password: String) async throws {
        try await apiClient.register(email: email, password: password)
    }

    func logout() {
        storage.clearAll()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func fetchExpenses(from: Date? = nil, to: Date? = nil) async throws -> [Expense] {
        if AppConfig.useMockData {
            return try await MockExpenseRepository.shared.fetchExpenses(from: from, to: to)
        }
        return try await apiClient.fetchExpenses(from: from, to: to)
    }

    @discardableResult
    func addExpense(
        amount: Double,
        currency: String = "USD",
        category: ExpenseCategory,
        note: String? = nil,
        date: Date = .now
    ) async throws -> Expense {
        if AppConfig.useMockData {
            return try await MockExpenseRepository.shared.addExpense(
                amount: amount,
                currency: currency,
                category: category,
                note: note,
                date: date
            )
        }

        let created = try await apiClient.addExpense(
            amount: amount,
            currency: currency,
            category: category,
            note: note,
            date: date
        )
        _ = try? await refreshAndCacheDefaultSummary()
        WidgetCenter.shared.reloadAllTimelines()
        return created
    }

    func deleteExpense(id: UUID) async throws {
        if AppConfig.useMockData {
            try await MockExpenseRepository.shared.deleteExpense(id: id)
            return
        }

        try await apiClient.deleteExpense(id: id)
        _ = try? await refreshAndCacheDefaultSummary()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func fetchSummary(
        period: String = "week",
        days: Int? = nil,
        topCategories: Int? = nil
    ) async throws -> ExpenseSummary {
        if AppConfig.useMockData {
            return try await MockExpenseRepository.shared.fetchSummary(
                period: period,
                days: days,
                topCategories: topCategories
            )
        }

        do {
            let summary = try await apiClient.fetchSummary(
                period: period,
                days: days,
                topCategories: topCategories
            )
            storage.saveSummary(summary)
            WidgetCenter.shared.reloadAllTimelines()
            return summary
        } catch {
            if let cached = storage.getSummary(forPeriod: period) {
                return cached
            }
            throw error
        }
    }

    func seedDemo() async throws {
        if AppConfig.useMockData {
            try await MockExpenseRepository.shared.seedDemo()
            return
        }

        try await apiClient.seedDemo()
        _ = try? await refreshAndCacheDefaultSummary()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Private Helpers

    @discardableResult
    private func refreshAndCacheDefaultSummary() async throws -> ExpenseSummary {
        let summary = try await apiClient.fetchSummary(period: "week")
        storage.saveSummary(summary)
        return summary
    }
}

// MARK: - MockExpenseRepository

final class MockExpenseRepository: ExpenseRepositoryProtocol, @unchecked Sendable {

    static let shared = MockExpenseRepository()

    private let lock = NSLock()
    private let storage: SharedStorage
    private var expenses: [Expense]

    init(
        storage: SharedStorage = .shared,
        initialExpenses: [Expense]? = nil
    ) {
        self.storage = storage
        self.expenses = initialExpenses ?? Self.defaultSampleExpenses()
    }

    @discardableResult
    func login(email: String, password: String) async throws -> AuthResponse {
        let mockResponse = AuthResponse(
            tokenType: "Bearer",
            accessToken: "mock-demo-bearer-token-\(UUID().uuidString)",
            refreshToken: "mock-demo-refresh-token",
            expiresIn: 3600,
            userId: "demo-user-id",
            email: email
        )
        storage.saveToken(mockResponse.accessToken)
        cacheCurrentSummary(period: "week", days: 7, topCategories: nil)
        WidgetCenter.shared.reloadAllTimelines()
        return mockResponse
    }

    func register(email: String, password: String) async throws {
        // No-op in mock mode; registration succeeds immediately for offline conference demos.
    }

    func logout() {
        storage.clearAll()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func fetchExpenses(from: Date? = nil, to: Date? = nil) async throws -> [Expense] {
        let snapshot = lock.withLock { expenses }

        return snapshot
            .filter { expense in
                if let from, expense.date < from { return false }
                if let to, expense.date > to { return false }
                return true
            }
            .sorted { $0.date > $1.date }
    }

    @discardableResult
    func addExpense(
        amount: Double,
        currency: String = "USD",
        category: ExpenseCategory,
        note: String? = nil,
        date: Date = .now
    ) async throws -> Expense {
        let newExpense = Expense(
            amount: amount,
            currency: currency,
            category: category,
            note: note,
            date: date
        )

        lock.withLock {
            expenses.insert(newExpense, at: 0)
        }

        cacheCurrentSummary(period: "week", days: 7, topCategories: nil)
        WidgetCenter.shared.reloadAllTimelines()
        return newExpense
    }

    func deleteExpense(id: UUID) async throws {
        lock.withLock {
            expenses.removeAll { $0.id == id }
        }

        cacheCurrentSummary(period: "week", days: 7, topCategories: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func fetchSummary(
        period: String = "week",
        days: Int? = nil,
        topCategories: Int? = nil
    ) async throws -> ExpenseSummary {
        let summary = buildSummary(period: period, days: days, topCategories: topCategories)
        storage.saveSummary(summary)
        WidgetCenter.shared.reloadAllTimelines()
        return summary
    }

    func seedDemo() async throws {
        lock.withLock {
            expenses = Self.defaultSampleExpenses()
        }

        cacheCurrentSummary(period: "week", days: 7, topCategories: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Summary Calculation & Sample Data

    @discardableResult
    private func cacheCurrentSummary(period: String, days: Int?, topCategories: Int?) -> ExpenseSummary {
        let summary = buildSummary(period: period, days: days, topCategories: topCategories)
        storage.saveSummary(summary)
        return summary
    }

    private func buildSummary(period: String, days: Int?, topCategories: Int?) -> ExpenseSummary {
        let resolvedDays: Int = {
            if let days, days > 0 { return days }
            switch period.lowercased() {
            case "day", "today": return 1
            case "week": return 7
            case "month": return 30
            case "year": return 365
            default: return 7
            }
        }()

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -resolvedDays,
            to: .now
        ) ?? .distantPast

        let filtered = lock.withLock {
            expenses.filter { $0.date >= cutoffDate }
        }

        let total = filtered.reduce(0.0) { $0 + $1.amount }
        let currency = filtered.first?.currency ?? "EGP"

        let grouped = Dictionary(grouping: filtered, by: \.category)
        var categorySummaries: [CategorySummary] = grouped.map { category, items in
            let catTotal = items.reduce(0.0) { $0 + $1.amount }
            let pct = total > 0 ? (catTotal / total) * 100.0 : 0.0
            return CategorySummary(
                category: category,
                total: catTotal,
                count: items.count,
                percentage: pct
            )
        }
        .sorted { $0.total > $1.total }

        if let topCategories, topCategories > 0, categorySummaries.count > topCategories {
            categorySummaries = Array(categorySummaries.prefix(topCategories))
        }

        return ExpenseSummary(
            period: period,
            days: resolvedDays,
            total: total,
            currency: currency,
            byCategory: categorySummaries
        )
    }

    static func defaultSampleExpenses(referenceDate: Date = .now) -> [Expense] {
        let calendar = Calendar.current
        func hoursAgo(_ hours: Int) -> Date {
            calendar.date(byAdding: .hour, value: -hours, to: referenceDate) ?? referenceDate
        }

        return [
            Expense(
                amount: 185.00,
                currency: "EGP",
                category: .food,
                note: "Specialty coffee & croissant",
                date: hoursAgo(2)
            ),
            Expense(
                amount: 340.00,
                currency: "EGP",
                category: .transport,
                note: "Airport rideshare",
                date: hoursAgo(6)
            ),
            Expense(
                amount: 1250.00,
                currency: "EGP",
                category: .shopping,
                note: "Wireless travel charger",
                date: hoursAgo(20)
            ),
            Expense(
                amount: 640.00,
                currency: "EGP",
                category: .food,
                note: "Team dinner after keynote",
                date: hoursAgo(28)
            ),
            Expense(
                amount: 850.00,
                currency: "EGP",
                category: .bills,
                note: "Cloud & fiber internet bill",
                date: hoursAgo(50)
            ),
            Expense(
                amount: 250.00,
                currency: "EGP",
                category: .entertainment,
                note: "IMAX movie ticket",
                date: hoursAgo(72)
            ),
            Expense(
                amount: 150.00,
                currency: "EGP",
                category: .other,
                note: "Conference notebook",
                date: hoursAgo(96)
            )
        ]
    }
}
