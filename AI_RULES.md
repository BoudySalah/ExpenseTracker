# 🤖 AI Assistant & Development Guidelines for Expense Tracker

These rules and architectural principles must be strictly followed when writing, modifying, or refactoring code in the **Expense Tracker** project.

---

## 1. Core Architectural Rules

### 1.1 Strict SwiftUI MVVM
- **Views are Passive**: Views must only render UI based on ViewModel state and forward user actions to ViewModel methods. Never perform network calls, database queries, or raw JSON parsing inside Views.
- **ViewModels use `@Observable` and `@MainActor`**: Use Swift's modern `@Observable` macro (iOS 17+) and mark ViewModels with `@MainActor`. Do not use deprecated `ObservableObject` or `@Published` unless retrofitting legacy targets.
- **Protocol-Driven Repositories**: ViewModels must never instantiate or invoke `APIClient` or `SharedStorage` directly. All data access must pass through `ExpenseRepositoryProtocol`.

### 1.2 Dual Mode Architecture (Live & Mock)
- Any new endpoint or feature added to `ExpenseRepositoryProtocol` **must** be implemented in both:
  1. `LiveExpenseRepository`: using real network calls via `APIClient`.
  2. `MockExpenseRepository`: in-memory thread-safe simulation with realistic behavior.
- Support `AppConfig.useMockData` so conference demos and offline tests continue to work without a network connection.

### 1.3 Strict Swift Concurrency & Thread Safety
- Mark types shared across actor boundaries with `Sendable`.
- Use `async/await` for asynchronous operations. Avoid completion handlers or GCD `DispatchQueue.main.async` in modern code.
- If thread synchronization is necessary in non-actor singletons (e.g. `MockExpenseRepository`, `SharedStorage`), use `NSLock` and `lock.withLock { ... }`.

---

## 2. Storage & Cross-Target Rules (WidgetKit & App Groups)

### 2.1 App Groups & Shared Storage
- Shared data between the main app and widget extensions must use the App Group suite: `SharedStorage.appGroupSuiteName` (`group.com.workshop.expensetracker`).
- Sensitive items (auth tokens) must be saved via `SharedStorage` into the Shared Keychain Access Group (`$(AppIdentifierPrefix)com.workshop.expensetracker.shared`), preserving the Simulator fallback.
- Cached summary data for widgets must be saved to `UserDefaults` using `SharedStorage.saveSummary(_:)`.

### 2.2 Timeline Invalidation
- Whenever an expense is added, deleted, or seeded, invoke:
  ```swift
  WidgetCenter.shared.reloadAllTimelines()
  ```
- Send appropriate `NotificationCenter` broadcasts (`.expensesDidChange`, `.authStateDidChange`) to keep decoupled views in sync.

---

## 3. SwiftUI & UI/UX Guidelines

### 3.1 Styling & System Integration
- Use Apple system colors, native controls (`List`, `Section`, `Form`, `NavigationStack`, `Menu`, `Toggle`), and SF Symbols.
- Support dynamic type, light/dark mode, and accessibility labels.
- Use `.contentTransition(.numericText())` for numerical values that change dynamically.
- Use `.presentationDetents([.medium, .large])` for entry and modal sheets.

### 3.2 Error Handling & User Feedback
- Display errors through clear, user-friendly inline error banners or alerts with retry buttons.
- Show non-blocking progress indicators (`ProgressView()`) during asynchronous operations.

---

## 4. Folder Structure Integrity

Respect the established repository layout:
```text
ExpenseTracker/
├── Shared/
│   ├── Models/         # Codable, Sendable domain models
│   ├── Networking/     # APIClient, Endpoints, Repository implementations
│   └── Storage/        # SharedStorage, Keychain & UserDefaults helpers
├── ExpenseWidget/      # WidgetKit extension views, providers, intents
└── ExpenseTracker/     # Main app Views, ViewModels, AppIntents, Assets
```
Never create loose files in the project root that belong to a specific module or layer.
