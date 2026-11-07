//
//  ExpenseModels.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import Foundation
import SwiftUI

// MARK: - ExpenseCategory

nonisolated enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case food
    case transport
    case shopping
    case bills
    case entertainment
    case other

    var id: String { rawValue }

    // MARK: Display & Styling

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Transport"
        case .shopping: return "Shopping"
        case .bills: return "Bills"
        case .entertainment: return "Entertainment"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .bills: return "bolt.fill"
        case .entertainment: return "tv.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var systemImage: String { icon }

    var color: Color {
        switch self {
        case .food: return .orange
        case .transport: return .blue
        case .shopping: return .pink
        case .bills: return .red
        case .entertainment: return .purple
        case .other: return .gray
        }
    }
}

// MARK: - Expense

struct Expense: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var amount: Double
    var currency: String
    var category: ExpenseCategory
    var note: String?
    var date: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        currency: String = "USD",
        category: ExpenseCategory,
        note: String? = nil,
        date: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.category = category
        self.note = note
        self.date = date
    }
}

// MARK: - CategorySummary

struct CategorySummary: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String { category.rawValue }
    let category: ExpenseCategory
    let total: Double
    let count: Int
    let percentage: Double

    init(
        category: ExpenseCategory,
        total: Double,
        count: Int = 0,
        percentage: Double = 0.0
    ) {
        self.category = category
        self.total = total
        self.count = count
        self.percentage = percentage
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case total
        case amount
        case count
        case percentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.category = try container.decode(ExpenseCategory.self, forKey: .category)
        if let totalValue = try container.decodeIfPresent(Double.self, forKey: .total) {
            self.total = totalValue
        } else {
            self.total = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0.0
        }
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        self.percentage = try container.decodeIfPresent(Double.self, forKey: .percentage) ?? 0.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(total, forKey: .total)
        try container.encode(count, forKey: .count)
        try container.encode(percentage, forKey: .percentage)
    }
}

// MARK: - ExpenseSummary

struct ExpenseSummary: Codable, Equatable, Hashable, Sendable {
    let period: String
    let days: Int
    let total: Double
    let currency: String
    let byCategory: [CategorySummary]

    init(
        period: String,
        days: Int,
        total: Double,
        currency: String = "USD",
        byCategory: [CategorySummary]
    ) {
        self.period = period
        self.days = days
        self.total = total
        self.currency = currency
        self.byCategory = byCategory
    }

    private enum CodingKeys: String, CodingKey {
        case period
        case days
        case total
        case currency
        case byCategory
        case byCategorySnake = "by_category"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.period = try container.decodeIfPresent(String.self, forKey: .period) ?? "week"
        self.days = try container.decodeIfPresent(Int.self, forKey: .days) ?? 7
        let decodedTotal = try container.decodeIfPresent(Double.self, forKey: .total) ?? 0.0
        self.total = decodedTotal
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"

        if let categories = try? container.decode([CategorySummary].self, forKey: .byCategory) {
            self.byCategory = categories
        } else if let categories = try? container.decode([CategorySummary].self, forKey: .byCategorySnake) {
            self.byCategory = categories
        } else if let dict = (try? container.decode([String: Double].self, forKey: .byCategory))
                    ?? (try? container.decode([String: Double].self, forKey: .byCategorySnake)) {
            self.byCategory = dict.compactMap { key, value in
                guard let category = ExpenseCategory(rawValue: key.lowercased()) else { return nil }
                let pct = decodedTotal > 0 ? (value / decodedTotal) * 100.0 : 0.0
                return CategorySummary(category: category, total: value, count: 0, percentage: pct)
            }
            .sorted { $0.total > $1.total }
        } else {
            self.byCategory = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(period, forKey: .period)
        try container.encode(days, forKey: .days)
        try container.encode(total, forKey: .total)
        try container.encode(currency, forKey: .currency)
        try container.encode(byCategory, forKey: .byCategory)
    }
}

// MARK: - AuthResponse

struct AuthResponse: Codable, Equatable, Hashable, Sendable {
    let tokenType: String?
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let userId: String?
    let email: String?

    var token: String { accessToken }

    init(
        tokenType: String? = "Bearer",
        accessToken: String,
        refreshToken: String? = nil,
        expiresIn: Int? = nil,
        userId: String? = nil,
        email: String? = nil
    ) {
        self.tokenType = tokenType
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.userId = userId
        self.email = email
    }

    private enum CodingKeys: String, CodingKey {
        case tokenType
        case tokenTypeSnake = "token_type"
        case token
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case expiresIn
        case expiresInSnake = "expires_in"
        case userId
        case userIdSnake = "user_id"
        case email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
            ?? container.decodeIfPresent(String.self, forKey: .tokenTypeSnake)

        if let accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) {
            self.accessToken = accessToken
        } else if let token = try container.decodeIfPresent(String.self, forKey: .token) {
            self.accessToken = token
        } else {
            self.accessToken = try container.decode(String.self, forKey: .accessTokenSnake)
        }

        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
        self.expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
            ?? container.decodeIfPresent(Int.self, forKey: .expiresInSnake)
        self.userId = try container.decodeIfPresent(String.self, forKey: .userId)
            ?? container.decodeIfPresent(String.self, forKey: .userIdSnake)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(tokenType, forKey: .tokenType)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(email, forKey: .email)
    }
}

// MARK: - APIErrorResponse

struct APIErrorResponse: Codable, LocalizedError, Equatable, Hashable, Sendable {
    let error: String?
    let message: String?
    let title: String?
    let detail: String?
    let statusCode: Int?
    let errors: [String: [String]]?

    init(
        error: String? = nil,
        message: String? = nil,
        title: String? = nil,
        detail: String? = nil,
        statusCode: Int? = nil,
        errors: [String: [String]]? = nil
    ) {
        self.error = error
        self.message = message
        self.title = title
        self.detail = detail
        self.statusCode = statusCode
        self.errors = errors
    }

    var errorDescription: String? {
        if let errors, !errors.isEmpty {
            let joined = errors.values.flatMap { $0 }.joined(separator: "\n")
            if !joined.isEmpty { return joined }
        }
        return message ?? detail ?? error ?? title ?? "An unexpected error occurred."
    }

    private enum CodingKeys: String, CodingKey {
        case error
        case message
        case title
        case detail
        case status
        case statusCode
        case statusCodeSnake = "status_code"
        case errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
            ?? container.decodeIfPresent(Int.self, forKey: .status)
            ?? container.decodeIfPresent(Int.self, forKey: .statusCodeSnake)
        self.errors = try container.decodeIfPresent([String: [String]].self, forKey: .errors)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(statusCode, forKey: .statusCode)
        try container.encodeIfPresent(errors, forKey: .errors)
    }
}
