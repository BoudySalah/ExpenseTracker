//
//  HomeViewModel.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import Foundation
import Observation

// MARK: - ExpenseDaySection

struct ExpenseDaySection: Identifiable, Equatable, Sendable {
    let id: Date
    let date: Date
    let title: String
    let dayTotal: Double
    let expenses: [Expense]
}

// MARK: - HomeViewModel

@Observable
@MainActor
final class HomeViewModel {

    // MARK: State

    var expenses: [Expense] = []
    var monthlySummary: ExpenseSummary?
    var todaySummary: ExpenseSummary?
    var isLoading: Bool = false
    var errorMessage: String?
    var isShowingAddSheet: Bool = false

    var useMockData: Bool = AppConfig.useMockData {
        didSet {
            guard AppConfig.useMockData != useMockData else { return }
            AppConfig.useMockData = useMockData
            Task { await refresh() }
        }
    }

    private let repositoryProvider: @MainActor () -> any ExpenseRepositoryProtocol
    private let storage: SharedStorage

    // MARK: Initialization

    init(
        repositoryProvider: (@MainActor () -> any ExpenseRepositoryProtocol)? = nil,
        storage: SharedStorage? = nil
    ) {
        self.repositoryProvider = repositoryProvider ?? { AppConfig.makeRepository() }
        let resolvedStorage = storage ?? .shared
        self.storage = resolvedStorage
        self.monthlySummary = resolvedStorage.getSummary(forPeriod: "month")
            ?? resolvedStorage.getSummary()
    }

    // MARK: Computed Properties

    var currencyCode: String {
        monthlySummary?.currency ?? expenses.first?.currency ?? "EGP"
    }

    /// Total spending for the current month / 30-day period.
    var monthlyTotal: Double {
        if let summaryTotal = monthlySummary?.total, summaryTotal > 0 || expenses.isEmpty {
            return summaryTotal
        }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return expenses
            .filter { $0.date >= cutoff }
            .reduce(0.0) { $0 + $1.amount }
    }

    /// Total spending recorded today.
    var todayTotal: Double {
        let calendar = Calendar.current
        let todayExpensesTotal = expenses
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0.0) { $0 + $1.amount }

        if todayExpensesTotal > 0 || !expenses.isEmpty {
            return todayExpensesTotal
        }
        return todaySummary?.total ?? 0.0
    }

    /// Top spending categories for the summary header pills.
    var topCategories: [CategorySummary] {
        if let categories = monthlySummary?.byCategory, !categories.isEmpty {
            return Array(categories.sorted { $0.total > $1.total }.prefix(4))
        }

        let total = monthlyTotal
        let grouped = Dictionary(grouping: expenses, by: \.category)
        return grouped.map { category, items in
            let sum = items.reduce(0.0) { $0 + $1.amount }
            let pct = total > 0 ? (sum / total) * 100.0 : 0.0
            return CategorySummary(
                category: category,
                total: sum,
                count: items.count,
                percentage: pct
            )
        }
        .sorted { $0.total > $1.total }
        .prefix(4)
        .map { $0 }
    }

    /// Expenses grouped by calendar day (newest day first).
    var groupedExpenses: [ExpenseDaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: expenses) { expense in
            calendar.startOfDay(for: expense.date)
        }

        return grouped.keys
            .sorted(by: >)
            .map { dayStart in
                let items = (grouped[dayStart] ?? []).sorted { $0.date > $1.date }
                let subtotal = items.reduce(0.0) { $0 + $1.amount }
                return ExpenseDaySection(
                    id: dayStart,
                    date: dayStart,
                    title: Self.sectionTitle(for: dayStart, calendar: calendar),
                    dayTotal: subtotal,
                    expenses: items
                )
            }
    }

    // MARK: Actions

    func loadInitialDataIfNeeded() async {
        guard expenses.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        let showSpinner = expenses.isEmpty && monthlySummary == nil
        if showSpinner {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if showSpinner {
                isLoading = false
            }
        }

        let repository = repositoryProvider()

        do {
            async let fetchedExpenses = repository.fetchExpenses(from: nil, to: nil)
            async let fetchedMonthly = repository.fetchSummary(
                period: "month",
                days: 30,
                topCategories: 4
            )
            async let fetchedToday = try? repository.fetchSummary(
                period: "day",
                days: 1,
                topCategories: nil
            )

            let (resolvedExpenses, resolvedMonthly, resolvedToday) = try await (
                fetchedExpenses,
                fetchedMonthly,
                fetchedToday
            )

            self.expenses = resolvedExpenses.sorted { $0.date > $1.date }
            self.monthlySummary = resolvedMonthly
            self.todaySummary = resolvedToday
        } catch is CancellationError {
            return
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func handleExpenseAdded(_ created: Expense) async {
        expenses.insert(created, at: 0)
        expenses.sort { $0.date > $1.date }
        await refreshSummariesQuietly()
    }

    func addExpense(
        amount: Double,
        currency: String = "EGP",
        category: ExpenseCategory,
        note: String?,
        date: Date = .now
    ) async {
        errorMessage = nil
        let repository = repositoryProvider()

        do {
            let created = try await repository.addExpense(
                amount: amount,
                currency: currency,
                category: category,
                note: note,
                date: date
            )
            await handleExpenseAdded(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteExpense(_ expense: Expense) async {
        errorMessage = nil
        let previousExpenses = expenses
        expenses.removeAll { $0.id == expense.id }

        let repository = repositoryProvider()
        do {
            try await repository.deleteExpense(id: expense.id)
            await refreshSummariesQuietly()
        } catch {
            expenses = previousExpenses
            errorMessage = error.localizedDescription
        }
    }

    func seedDemoData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let repository = repositoryProvider()
        do {
            try await repository.seedDemo()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        repositoryProvider().logout()
    }

    // MARK: Private Helpers

    private func refreshSummariesQuietly() async {
        let repository = repositoryProvider()
        if let updatedMonthly = try? await repository.fetchSummary(
            period: "month",
            days: 30,
            topCategories: 4
        ) {
            monthlySummary = updatedMonthly
        }
        if let updatedToday = try? await repository.fetchSummary(
            period: "day",
            days: 1,
            topCategories: nil
        ) {
            todaySummary = updatedToday
        }
    }

    private static func sectionTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}
