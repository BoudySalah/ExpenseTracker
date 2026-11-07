//
//  AddExpenseView.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import SwiftUI
import Observation
import WidgetKit

// MARK: - AddExpenseViewModel

@Observable
@MainActor
final class AddExpenseViewModel {
    var amountText: String = ""
    var currency: String = "EGP"
    var selectedCategory: ExpenseCategory = .food
    var note: String = ""
    var date: Date = .now
    var isSaving: Bool = false
    var errorMessage: String?

    private let repositoryProvider: @MainActor () -> any ExpenseRepositoryProtocol

    init(
        currency: String = "EGP",
        repositoryProvider: (@MainActor () -> any ExpenseRepositoryProtocol)? = nil
    ) {
        self.currency = currency
        self.repositoryProvider = repositoryProvider ?? { AppConfig.makeRepository() }
    }

    var parsedAmount: Double? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            return nil
        }
        return value
    }

    var canSave: Bool {
        parsedAmount != nil && !isSaving
    }

    func saveExpense() async -> Expense? {
        guard let amount = parsedAmount else {
            errorMessage = "Please enter a valid amount greater than 0."
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = repositoryProvider()

        do {
            let created = try await repository.addExpense(
                amount: amount,
                currency: currency,
                category: selectedCategory,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                date: date
            )
            WidgetCenter.shared.reloadAllTimelines()
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - AddExpenseView

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddExpenseViewModel
    @FocusState private var isAmountFocused: Bool

    private let onExpenseAdded: ((Expense) -> Void)?

    init(
        currency: String = "EGP",
        onExpenseAdded: ((Expense) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: AddExpenseViewModel(currency: currency))
        self.onExpenseAdded = onExpenseAdded
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                categorySection
                detailsSection

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    saveButton
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await performSave() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                }
            }
            .onAppear {
                isAmountFocused = true
            }
        }
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section("Amount") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(viewModel.currency)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)

                TextField("0.00", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .focused($isAmountFocused)
            }
            .padding(.vertical, 6)
        }
    }

    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $viewModel.selectedCategory) {
                ForEach(ExpenseCategory.allCases) { category in
                    Label {
                        Text(category.displayName)
                    } icon: {
                        Image(systemName: category.icon)
                            .foregroundStyle(category.color)
                    }
                    .tag(category)
                }
            }
            .pickerStyle(.navigationLink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ExpenseCategory.allCases) { category in
                        let isSelected = viewModel.selectedCategory == category
                        Button {
                            withAnimation(.snappy) {
                                viewModel.selectedCategory = category
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon)
                                    .font(.caption.weight(.semibold))
                                Text(category.displayName)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? .white : category.color)
                            .background(
                                isSelected ? category.color : category.color.opacity(0.14),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Optional note (e.g., Lunch, Uber, Groceries)", text: $viewModel.note)
                .textInputAutocapitalization(.sentences)

            DatePicker(
                "Date",
                selection: $viewModel.date,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    private var saveButton: some View {
        Button {
            Task { await performSave() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(viewModel.isSaving ? "Saving..." : "Save Expense")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(!viewModel.canSave)
    }

    // MARK: - Actions

    private func performSave() async {
        isAmountFocused = false
        if let createdExpense = await viewModel.saveExpense() {
            onExpenseAdded?(createdExpense)
            dismiss()
        }
    }
}

#Preview {
    AddExpenseView()
}
