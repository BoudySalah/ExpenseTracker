//
//  APIClient.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import Foundation

// MARK: - APIError

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid endpoint URL."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "The requested resource was not found."
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Request failed with status code \(statusCode)."
        case .decodingError(let error):
            return "Failed to parse server response: \(error.localizedDescription)"
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - Request Payloads

struct AuthCredentialsRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct CreateExpenseRequest: Codable, Sendable {
    let amount: Double
    let currency: String
    let category: ExpenseCategory
    let note: String?
    let date: Date
}

// MARK: - APIClient

final class APIClient: Sendable {

    // MARK: Singleton & Properties

    static let shared = APIClient()

    let baseURL = URL(string: "https://expensetracker-workshop.runasp.net")!

    private let session: URLSession
    private let storage: SharedStorage
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: Initialization

    init(
        session: URLSession = .shared,
        storage: SharedStorage = .shared
    ) {
        self.session = session
        self.storage = storage

        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        self.encoder = jsonEncoder

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFractional.date(from: dateString) {
                return date
            }

            let isoStandard = ISO8601DateFormatter()
            isoStandard.formatOptions = [.withInternetDateTime]
            if let date = isoStandard.date(from: dateString) {
                return date
            }

            let fallbackFormatter = DateFormatter()
            fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
            fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            for format in [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd"
            ] {
                fallbackFormatter.dateFormat = format
                if let date = fallbackFormatter.date(from: dateString) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO-8601 date string: \(dateString)"
            )
        }
        self.decoder = jsonDecoder
    }

    // MARK: - Auth Endpoints

    /// Authenticates a user via `POST /login` and stores the Bearer token in `SharedStorage`.
    @discardableResult
    func login(email: String, password: String) async throws -> AuthResponse {
        let payload = AuthCredentialsRequest(email: email, password: password)
        let body = try encoder.encode(payload)
        let request = try makeRequest(
            path: "/login",
            method: "POST",
            body: body,
            requiresAuth: false
        )
        let authResponse: AuthResponse = try await perform(request)
        storage.saveToken(authResponse.accessToken)
        return authResponse
    }

    /// Registers a new user account via `POST /register`.
    func register(email: String, password: String) async throws {
        let payload = AuthCredentialsRequest(email: email, password: password)
        let body = try encoder.encode(payload)
        let request = try makeRequest(
            path: "/register",
            method: "POST",
            body: body,
            requiresAuth: false
        )
        try await performVoid(request)
    }

    // MARK: - Expense Endpoints

    /// Fetches the authenticated user's expenses via `GET /expenses`, optionally filtered by `from` and `to` dates.
    func fetchExpenses(from: Date? = nil, to: Date? = nil) async throws -> [Expense] {
        var queryItems: [URLQueryItem] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        if let from {
            queryItems.append(URLQueryItem(name: "from", value: isoFormatter.string(from: from)))
        }
        if let to {
            queryItems.append(URLQueryItem(name: "to", value: isoFormatter.string(from: to)))
        }

        let request = try makeRequest(
            path: "/expenses",
            method: "GET",
            queryItems: queryItems
        )
        return try await perform(request)
    }

    /// Creates a new expense via `POST /expenses` using individual parameters.
    @discardableResult
    func addExpense(
        amount: Double,
        currency: String = "USD",
        category: ExpenseCategory,
        note: String? = nil,
        date: Date = .now
    ) async throws -> Expense {
        let payload = CreateExpenseRequest(
            amount: amount,
            currency: currency,
            category: category,
            note: note,
            date: date
        )
        let body = try encoder.encode(payload)
        let request = try makeRequest(
            path: "/expenses",
            method: "POST",
            body: body
        )
        return try await perform(request)
    }

    /// Creates a new expense via `POST /expenses` from an `Expense` model.
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

    /// Deletes a single expense by ID via `DELETE /expenses/{id}`.
    func deleteExpense(id: UUID) async throws {
        let request = try makeRequest(
            path: "/expenses/\(id.uuidString)",
            method: "DELETE"
        )
        try await performVoid(request)
    }

    // MARK: - Summary Endpoint

    /// Fetches spending summary via `GET /summary` with `period`, optional `days`, and `topCategories` query parameters,
    /// and caches the result in `SharedStorage` for offline Widget access.
    func fetchSummary(
        period: String = "week",
        days: Int? = nil,
        topCategories: Int? = nil
    ) async throws -> ExpenseSummary {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "period", value: period)
        ]
        if let days {
            queryItems.append(URLQueryItem(name: "days", value: String(days)))
        }
        if let topCategories {
            queryItems.append(URLQueryItem(name: "topCategories", value: String(topCategories)))
        }

        let request = try makeRequest(
            path: "/summary",
            method: "GET",
            queryItems: queryItems
        )
        let summary: ExpenseSummary = try await perform(request)
        storage.saveSummary(summary)
        return summary
    }

    // MARK: - Demo Seed Endpoint

    /// Seeds realistic sample expenses for the authenticated user via `POST /seed-demo`.
    func seedDemo() async throws {
        let request = try makeRequest(
            path: "/seed-demo",
            method: "POST"
        )
        try await performVoid(request)
    }

    // MARK: - Private Networking Helpers

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuth: Bool = true
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if requiresAuth {
            guard let token = storage.getToken(), !token.isEmpty else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await executeDataRequest(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func performVoid(_ request: URLRequest) async throws {
        _ = try await executeDataRequest(request)
    }

    private func executeDataRequest(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            if let apiError = try? decoder.decode(APIErrorResponse.self, from: data),
               let description = apiError.errorDescription {
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: description)
            }
            let rawMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: rawMessage)
        }
    }
}
