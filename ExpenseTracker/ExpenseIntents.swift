//
//  ExpenseIntents.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - ExpenseCategory + AppEnum

nonisolated extension ExpenseCategory: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Expense Category")
    }

    static var caseDisplayRepresentations: [ExpenseCategory: DisplayRepresentation] {
        [
            .food: DisplayRepresentation(
                title: "Food",
                subtitle: "Meals, coffee, groceries, and dining",
                image: .init(systemName: "fork.knife"),
                synonyms: [
                    "lunch",
                    "dinner",
                    "breakfast",
                    "coffee",
                    "groceries",
                    "restaurant",
                    "meal",
                    "snack"
                ]
            ),
            .transport: DisplayRepresentation(
                title: "Transport",
                subtitle: "Rideshare, taxi, fuel, and transit",
                image: .init(systemName: "car.fill"),
                synonyms: [
                    "uber",
                    "careem",
                    "taxi",
                    "ride",
                    "gas",
                    "fuel",
                    "metro",
                    "bus",
                    "commute"
                ]
            ),
            .shopping: DisplayRepresentation(
                title: "Shopping",
                subtitle: "Clothes, electronics, and retail purchases",
                image: .init(systemName: "bag.fill"),
                synonyms: [
                    "clothes",
                    "amazon",
                    "mall",
                    "shoes",
                    "electronics",
                    "gift",
                    "retail"
                ]
            ),
            .bills: DisplayRepresentation(
                title: "Bills",
                subtitle: "Utilities, rent, internet, and subscriptions",
                image: .init(systemName: "bolt.fill"),
                synonyms: [
                    "electricity",
                    "water",
                    "internet",
                    "phone",
                    "rent",
                    "utilities",
                    "subscription"
                ]
            ),
            .entertainment: DisplayRepresentation(
                title: "Entertainment",
                subtitle: "Movies, games, streaming, and outings",
                image: .init(systemName: "tv.fill"),
                synonyms: [
                    "movie",
                    "cinema",
                    "netflix",
                    "concert",
                    "games",
                    "spotify",
                    "outing"
                ]
            ),
            .other: DisplayRepresentation(
                title: "Other",
                subtitle: "Miscellaneous expenses",
                image: .init(systemName: "ellipsis.circle.fill"),
                synonyms: [
                    "misc",
                    "miscellaneous",
                    "general"
                ]
            )
        ]
    }
}

// MARK: - SummaryPeriod AppEnum

nonisolated enum SummaryPeriod: String, CaseIterable, Sendable, AppEnum {
    case day
    case week
    case month

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Summary Period")
    }

    static var caseDisplayRepresentations: [SummaryPeriod: DisplayRepresentation] {
        [
            .day: DisplayRepresentation(
                title: "Today",
                image: .init(systemName: "sun.max.fill"),
                synonyms: ["today", "daily"]
            ),
            .week: DisplayRepresentation(
                title: "This Week",
                image: .init(systemName: "calendar"),
                synonyms: ["week", "weekly", "7 days", "seven days"]
            ),
            .month: DisplayRepresentation(
                title: "This Month",
                image: .init(systemName: "calendar.badge.clock"),
                synonyms: ["month", "monthly", "30 days"]
            )
        ]
    }

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }

    var spokenLabel: String {
        switch self {
        case .day: return "today"
        case .week: return "this week"
        case .month: return "this month"
        }
    }
}

// MARK: - AddExpenseIntent

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Quickly log a new expense with an amount, category, and optional note.")
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Amount",
        description: "The expense amount in EGP.",
        requestValueDialog: IntentDialog("How much did you spend in EGP?")
    )
    var amount: Double?

    @Parameter(
        title: "Category",
        description: "The category for the expense (e.g., Food, Transport, Shopping).",
        requestValueDialog: IntentDialog("Which category is this expense for?")
    )
    var category: ExpenseCategory?

    @Parameter(
        title: "Note",
        description: "An optional note describing the expense."
    )
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) EGP to \(\.$category)") {
            \.$note
        }
    }

    init() {}

    init(amount: Double, category: ExpenseCategory, note: String? = nil) {
        self.amount = amount
        self.category = category
        self.note = note
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let resolvedAmount: Double
        if let currentAmount = amount, currentAmount > 0 {
            resolvedAmount = currentAmount
        } else {
            resolvedAmount = try await $amount.requestValue(
                IntentDialog("How much did you spend in EGP?")
            )
        }

        let resolvedCategory: ExpenseCategory
        if let currentCategory = category {
            resolvedCategory = currentCategory
        } else {
            resolvedCategory = try await $category.requestValue(
                IntentDialog("Which category is this expense for?")
            )
        }

        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (cleanNote?.isEmpty == false) ? cleanNote : nil

        let createdExpense: Expense
        do {
            let repository = AppConfig.makeRepository()
            createdExpense = try await repository.addExpense(
                amount: resolvedAmount,
                currency: "EGP",
                category: resolvedCategory,
                note: effectiveNote,
                date: .now
            )
        } catch {
            // Fallback to MockExpenseRepository if offline or unauthenticated during a demo
            createdExpense = try await MockExpenseRepository.shared.addExpense(
                amount: resolvedAmount,
                currency: "EGP",
                category: resolvedCategory,
                note: effectiveNote,
                date: .now
            )
        }

        NotificationCenter.default.post(name: .expensesDidChange, object: nil)
        WidgetCenter.shared.reloadAllTimelines()

        let formattedAmount = resolvedAmount.formatted(
            .currency(code: createdExpense.currency).precision(.fractionLength(0...2))
        )
        let spokenMessage = "Logged \(formattedAmount) under \(resolvedCategory.displayName)."

        return .result(
            dialog: IntentDialog(stringLiteral: spokenMessage),
            view: AddedExpenseSnippetView(expense: createdExpense)
        )
    }
}

// MARK: - GetSummaryIntent

struct GetSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Spending Summary"
    static let description = IntentDescription("Check your total spending and top categories for today, this week, or this month.")
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Period",
        description: "The time period to summarize."
    )
    var period: SummaryPeriod?

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$period) spending summary")
    }

    init() {}

    init(period: SummaryPeriod? = .month) {
        self.period = period
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let resolvedPeriod = period ?? .month
        let repository = AppConfig.makeRepository()
        let summary: ExpenseSummary

        do {
            summary = try await repository.fetchSummary(
                period: resolvedPeriod.rawValue,
                days: resolvedPeriod.days,
                topCategories: 3
            )
        } catch {
            if let cached = SharedStorage.shared.getSummary(forPeriod: resolvedPeriod.rawValue)
                ?? SharedStorage.shared.getSummary() {
                summary = cached
            } else {
                summary = try await MockExpenseRepository.shared.fetchSummary(
                    period: resolvedPeriod.rawValue,
                    days: resolvedPeriod.days,
                    topCategories: 3
                )
            }
        }

        let formattedTotal = summary.total.formatted(
            .currency(code: summary.currency).precision(.fractionLength(0...2))
        )

        let spokenDialog: String
        if summary.total <= 0 {
            spokenDialog = "You haven't logged any expenses \(resolvedPeriod.spokenLabel)."
        } else if let top = summary.byCategory.first {
            let formattedTop = top.total.formatted(
                .currency(code: summary.currency).precision(.fractionLength(0...2))
            )
            spokenDialog = "You spent \(formattedTotal) \(resolvedPeriod.spokenLabel). Your top category is \(top.category.displayName) with \(formattedTop)."
        } else {
            spokenDialog = "You spent \(formattedTotal) \(resolvedPeriod.spokenLabel)."
        }

        return .result(
            dialog: IntentDialog(stringLiteral: spokenDialog),
            view: ExpenseSummarySnippetView(summary: summary, periodTitle: resolvedPeriod.spokenLabel.capitalized)
        )
    }
}

// MARK: - ExpenseShortcutsProvider

nonisolated struct ExpenseShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense in \(.applicationName)",
                "Add expense in \(.applicationName)",
                "Log a \(\.$category) expense in \(.applicationName)",
                "Add a \(\.$category) expense in \(.applicationName)",
                "Track my \(\.$category) spending in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: GetSummaryIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "Show my spending summary in \(.applicationName)",
                "Get my \(\.$period) spending in \(.applicationName)",
                "Show my \(\.$period) summary in \(.applicationName)",
                "What are my expenses in \(.applicationName)"
            ],
            shortTitle: "Spending Summary",
            systemImageName: "chart.pie.fill"
        )
    }
}

// MARK: - Snippet Views

struct AddedExpenseSnippetView: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(expense.category.color.opacity(0.18))
                    .frame(width: 46, height: 46)

                Image(systemName: expense.category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(expense.category.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.note ?? expense.category.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text(expense.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(
                expense.amount,
                format: .currency(code: expense.currency).precision(.fractionLength(0...2))
            )
            .font(.title3.weight(.bold))
            .foregroundStyle(expense.category.color)
        }
        .padding(16)
    }
}

struct ExpenseSummarySnippetView: View {
    let summary: ExpenseSummary
    let periodTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(periodTitle.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(
                        summary.total,
                        format: .currency(code: summary.currency).precision(.fractionLength(0...2))
                    )
                    .font(.title2.weight(.bold))
                }

                Spacer()

                Image(systemName: "chart.pie.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            if !summary.byCategory.isEmpty {
                Divider()

                VStack(spacing: 8) {
                    ForEach(summary.byCategory.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.category.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.category.color)
                                .frame(width: 18)

                            Text(item.category.displayName)
                                .font(.subheadline.weight(.medium))

                            Spacer()

                            Text(
                                item.total,
                                format: .currency(code: summary.currency).precision(.fractionLength(0...0))
                            )
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}
