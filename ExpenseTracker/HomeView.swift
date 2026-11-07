//
//  HomeView.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.expenses.isEmpty {
                    loadingStateView
                } else {
                    expenseListView
                }
            }
            .navigationTitle("Expenses")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle(isOn: $viewModel.useMockData) {
                            Label("Offline Mock Mode", systemImage: "sparkles")
                        }

                        Button {
                            Task { await viewModel.seedDemoData() }
                        } label: {
                            Label("Seed Demo Expenses", systemImage: "wand.and.stars")
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.logout()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add Expense")
                }
            }
            .sheet(isPresented: $viewModel.isShowingAddSheet) {
                AddExpenseView { createdExpense in
                    Task {
                        await viewModel.handleExpenseAdded(createdExpense)
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .task {
                await viewModel.loadInitialDataIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .expensesDidChange)) { _ in
                Task {
                    await viewModel.refresh()
                }
            }
        }
    }

    // MARK: - Main List & Summary Header

    private var expenseListView: some View {
        List {
            Section {
                summaryHeaderCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") {
                            Task { await viewModel.refresh() }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }

            if viewModel.groupedExpenses.isEmpty {
                Section {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(viewModel.groupedExpenses) { daySection in
                    Section {
                        ForEach(daySection.expenses) { expense in
                            ExpenseRowView(expense: expense)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task {
                                            await viewModel.deleteExpense(expense)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(daySection.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .textCase(nil)

                            Spacer()

                            Text(
                                daySection.dayTotal,
                                format: .currency(code: viewModel.currencyCode)
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Summary Header Card

    private var summaryHeaderCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("MONTHLY TOTAL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))

                        if viewModel.useMockData {
                            Text("DEMO")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.22), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    Text(
                        viewModel.monthlyTotal,
                        format: .currency(code: viewModel.currencyCode)
                    )
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("TODAY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    Text(
                        viewModel.todayTotal,
                        format: .currency(code: viewModel.currencyCode)
                    )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    .contentTransition(.numericText())
                }
            }

            if !viewModel.topCategories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Categories")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.topCategories) { item in
                                TopCategoryPillView(
                                    summary: item,
                                    currencyCode: viewModel.currencyCode
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .shadow(color: .indigo.opacity(0.22), radius: 12, y: 6)
        .padding(.vertical, 4)
    }

    // MARK: - Loading & Empty States

    private var loadingStateView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading your expenses...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Expenses Yet", systemImage: "tray")
        } description: {
            Text("Add your first expense or seed realistic sample data to explore summaries and widgets.")
        } actions: {
            HStack(spacing: 12) {
                Button("Add Expense") {
                    viewModel.isShowingAddSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("Seed Demo Data") {
                    Task { await viewModel.seedDemoData() }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - TopCategoryPillView

struct TopCategoryPillView: View {
    let summary: CategorySummary
    let currencyCode: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: summary.category.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(summary.category.color)
                .frame(width: 22, height: 22)
                .background(.white, in: Circle())

            Text(summary.category.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text(
                summary.total,
                format: .currency(code: currencyCode).precision(.fractionLength(0...2))
            )
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.18), in: Capsule())
    }
}

// MARK: - ExpenseRowView

struct ExpenseRowView: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(expense.category.color.opacity(0.15))
                    .frame(width: 42, height: 42)

                Image(systemName: expense.category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(expense.category.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text( primaryTitle )
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(expense.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(expense.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(
                expense.amount,
                format: .currency(code: expense.currency)
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private var primaryTitle: String {
        if let note = expense.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return note
        }
        return expense.category.displayName
    }
}

#Preview {
    HomeView()
}
