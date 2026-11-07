//
//  ExpenseWidget.swift
//  ExpenseWidget
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - WidgetPeriodOption

nonisolated enum WidgetPeriodOption: String, Codable, CaseIterable, Sendable, AppEnum {
    case today
    case month

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Spending Period")
    }

    static var caseDisplayRepresentations: [WidgetPeriodOption: DisplayRepresentation] {
        [
            .today: DisplayRepresentation(
                title: "Today",
                subtitle: "Today's total expenses",
                image: .init(systemName: "sun.max.fill")
            ),
            .month: DisplayRepresentation(
                title: "This Month",
                subtitle: "Last 30 days total and top categories",
                image: .init(systemName: "calendar")
            )
        ]
    }

    var apiPeriod: String {
        switch self {
        case .today: return "day"
        case .month: return "month"
        }
    }

    var days: Int {
        switch self {
        case .today: return 1
        case .month: return 30
        }
    }

    var badgeTitle: String {
        switch self {
        case .today: return "TODAY"
        case .month: return "THIS MONTH"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .month: return "calendar"
        }
    }
}

// MARK: - SummaryWidgetConfigurationIntent

struct SummaryWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Spending Summary" }
    static var description: IntentDescription {
        IntentDescription("Displays your total spending and top categories for Today or This Month.")
    }

    @Parameter(title: "Period", default: .month)
    var period: WidgetPeriodOption

    init() {
        self.period = .month
    }

    init(period: WidgetPeriodOption) {
        self.period = period
    }
}

// MARK: - ExpenseWidgetEntry

struct ExpenseWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: SummaryWidgetConfigurationIntent
    let summary: ExpenseSummary
    let isCachedOffline: Bool

    static func sample(for period: WidgetPeriodOption = .month) -> ExpenseWidgetEntry {
        let sampleCategories: [CategorySummary] = [
            CategorySummary(category: .shopping, total: 1250, count: 2, percentage: 41.0),
            CategorySummary(category: .bills, total: 850, count: 1, percentage: 28.0),
            CategorySummary(category: .food, total: 640, count: 3, percentage: 21.0)
        ]
        let sampleTotal: Double = period == .today ? 525.0 : 3040.0
        return ExpenseWidgetEntry(
            date: .now,
            configuration: SummaryWidgetConfigurationIntent(period: period),
            summary: ExpenseSummary(
                period: period.apiPeriod,
                days: period.days,
                total: sampleTotal,
                currency: "EGP",
                byCategory: sampleCategories
            ),
            isCachedOffline: false
        )
    }
}

// MARK: - ExpenseWidgetProvider

struct ExpenseWidgetProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> ExpenseWidgetEntry {
        ExpenseWidgetEntry.sample(for: .month)
    }

    func snapshot(
        for configuration: SummaryWidgetConfigurationIntent,
        in context: Context
    ) async -> ExpenseWidgetEntry {
        if context.isPreview {
            return ExpenseWidgetEntry.sample(for: configuration.period)
        }
        return await loadEntry(for: configuration)
    }

    func timeline(
        for configuration: SummaryWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<ExpenseWidgetEntry> {
        let entry = await loadEntry(for: configuration)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    // MARK: Data Loading with SharedStorage Offline Fallback

    private func loadEntry(for configuration: SummaryWidgetConfigurationIntent) async -> ExpenseWidgetEntry {
        let option = configuration.period

        if AppConfig.useMockData {
            if let mockSummary = try? await MockExpenseRepository.shared.fetchSummary(
                period: option.apiPeriod,
                days: option.days,
                topCategories: 3
            ) {
                return ExpenseWidgetEntry(
                    date: .now,
                    configuration: configuration,
                    summary: mockSummary,
                    isCachedOffline: false
                )
            }
        }

        do {
            let liveSummary = try await APIClient.shared.fetchSummary(
                period: option.apiPeriod,
                days: option.days,
                topCategories: 3
            )
            SharedStorage.shared.saveSummary(liveSummary)
            return ExpenseWidgetEntry(
                date: .now,
                configuration: configuration,
                summary: liveSummary,
                isCachedOffline: false
            )
        } catch {
            if let cached = SharedStorage.shared.getSummary(forPeriod: option.apiPeriod)
                ?? SharedStorage.shared.getSummary() {
                return ExpenseWidgetEntry(
                    date: .now,
                    configuration: configuration,
                    summary: cached,
                    isCachedOffline: true
                )
            }

            return ExpenseWidgetEntry(
                date: .now,
                configuration: configuration,
                summary: ExpenseSummary(
                    period: option.apiPeriod,
                    days: option.days,
                    total: 0,
                    currency: "EGP",
                    byCategory: []
                ),
                isCachedOffline: true
            )
        }
    }
}

// MARK: - ExpenseWidgetEntryView

struct ExpenseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: ExpenseWidgetProvider.Entry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidgetView
        default:
            smallWidgetView
        }
    }

    // MARK: .systemSmall Layout (Total + Period Badge)

    private var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: entry.configuration.period.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue)

                Text(entry.configuration.period.badgeTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if entry.isCachedOffline {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.12), in: Capsule())

            Spacer(minLength: 8)

            Text("Total Spent")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(
                entry.summary.total,
                format: .currency(code: entry.summary.currency).precision(.fractionLength(0...0))
            )
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())

            Spacer(minLength: 6)

            if let topCategory = entry.summary.byCategory.first {
                HStack(spacing: 5) {
                    Image(systemName: topCategory.category.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(topCategory.category.color)

                    Text(topCategory.category.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No expenses recorded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: .systemMedium Layout (Total + Top 3 Categories)

    private var mediumWidgetView: some View {
        HStack(spacing: 16) {
            // Left Column: Period Badge & Total
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: entry.configuration.period.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)

                    Text(entry.configuration.period.badgeTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12), in: Capsule())

                Spacer(minLength: 2)

                Text("Total Spent")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(
                    entry.summary.total,
                    format: .currency(code: entry.summary.currency).precision(.fractionLength(0...0))
                )
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .contentTransition(.numericText())

                Spacer(minLength: 2)

                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isCachedOffline ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(entry.isCachedOffline ? "Cached Offline" : "Synced")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Right Column: Top 3 Categories
            VStack(alignment: .leading, spacing: 8) {
                Text("TOP CATEGORIES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                let topThree = Array(entry.summary.byCategory.prefix(3))
                if topThree.isEmpty {
                    Spacer()
                    Text("No category data yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(topThree) { item in
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(item.category.color.opacity(0.16))
                                    .frame(width: 24, height: 24)
                                Image(systemName: item.category.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(item.category.color)
                            }

                            Text(item.category.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(
                                item.total,
                                format: .currency(code: entry.summary.currency).precision(.fractionLength(0...0))
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ExpenseWidget

struct ExpenseWidget: Widget {
    let kind: String = "ExpenseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SummaryWidgetConfigurationIntent.self,
            provider: ExpenseWidgetProvider()
        ) { entry in
            ExpenseWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Spending Summary")
        .description("View today's or this month's total expenses and top categories.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small - Month", as: .systemSmall) {
    ExpenseWidget()
} timeline: {
    ExpenseWidgetEntry.sample(for: .month)
    ExpenseWidgetEntry.sample(for: .today)
}

#Preview("Medium - Month", as: .systemMedium) {
    ExpenseWidget()
} timeline: {
    ExpenseWidgetEntry.sample(for: .month)
}
