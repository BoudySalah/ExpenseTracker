//
//  AuthView.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import SwiftUI
import Observation

// MARK: - AuthMode

enum AuthMode: String, CaseIterable, Identifiable {
    case login = "Sign In"
    case register = "Create Account"

    var id: String { rawValue }
}

// MARK: - AuthViewModel

@Observable
@MainActor
final class AuthViewModel {
    var mode: AuthMode = .login
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var useMockData: Bool = AppConfig.useMockData {
        didSet {
            AppConfig.useMockData = useMockData
        }
    }

    private let storage: SharedStorage

    init(storage: SharedStorage? = nil) {
        self.storage = storage ?? .shared
    }

    var isFormValid: Bool {
        if useMockData { return true }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@"), password.count >= 6 else {
            return false
        }
        if mode == .register {
            return password == confirmPassword
        }
        return true
    }

    func submit(onSuccess: @escaping () -> Void) async {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if !useMockData {
            guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
                errorMessage = "Please enter a valid email address."
                return
            }
            guard password.count >= 6 else {
                errorMessage = "Password must be at least 6 characters."
                return
            }
            if mode == .register && password != confirmPassword {
                errorMessage = "Passwords do not match."
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        let repository = AppConfig.makeRepository()
        let effectiveEmail = trimmedEmail.isEmpty ? "demo@workshop.dev" : trimmedEmail

        do {
            if mode == .register {
                try await repository.register(email: effectiveEmail, password: password)
            }
            let authResponse = try await repository.login(email: effectiveEmail, password: password)
            storage.saveToken(authResponse.accessToken)
            onSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func continueWithOfflineDemo(onSuccess: @escaping () -> Void) async {
        useMockData = true
        await submit(onSuccess: onSuccess)
    }
}

// MARK: - AuthView

struct AuthView: View {
    @State private var viewModel = AuthViewModel()
    @FocusState private var focusedField: Field?

    private let onAuthenticated: () -> Void

    private enum Field: Hashable {
        case email
        case password
        case confirmPassword
    }

    init(onAuthenticated: @escaping () -> Void = {}) {
        self.onAuthenticated = onAuthenticated
    }

    init(isAuthenticated: Binding<Bool>) {
        self.onAuthenticated = {
            isAuthenticated.wrappedValue = true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection

                    Picker("Authentication Mode", selection: $viewModel.mode) {
                        ForEach(AuthMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.mode) {
                        viewModel.errorMessage = nil
                    }

                    formSection

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(message: errorMessage)
                    }

                    actionButtonsSection

                    demoModeSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.25), radius: 12, y: 6)

                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Expense Tracker")
                .font(.largeTitle.bold())

            Text(
                viewModel.mode == .login
                    ? "Sign in to sync your expenses and widgets"
                    : "Create an account to start tracking your spending"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                TextField("Email address", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                SecureField("Password (min. 6 characters)", text: $viewModel.password)
                    .textContentType(viewModel.mode == .register ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(viewModel.mode == .register ? .next : .go)
                    .onSubmit {
                        if viewModel.mode == .register {
                            focusedField = .confirmPassword
                        } else {
                            Task { await viewModel.submit(onSuccess: onAuthenticated) }
                        }
                    }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            if viewModel.mode == .register {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    SecureField("Confirm Password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await viewModel.submit(onSuccess: onAuthenticated) }
                        }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: viewModel.mode)
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actionButtonsSection: some View {
        Button {
            focusedField = nil
            Task {
                await viewModel.submit(onSuccess: onAuthenticated)
            }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.mode == .login ? "Sign In" : "Create Account")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(viewModel.isLoading || !viewModel.isFormValid)
    }

    private var demoModeSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.vertical, 4)

            Toggle(isOn: $viewModel.useMockData) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offline Conference Demo Mode")
                            .font(.subheadline.weight(.medium))
                        Text("Uses MockExpenseRepository without network calls")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            Button {
                focusedField = nil
                Task {
                    await viewModel.continueWithOfflineDemo(onSuccess: onAuthenticated)
                }
            } label: {
                Label("Continue with Instant Demo Data", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .disabled(viewModel.isLoading)
        }
    }
}

#Preview {
    AuthView()
}
