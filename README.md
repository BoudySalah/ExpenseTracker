# 💳 Expense Tracker

[![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-blue.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![Swift 5.9 / 6.0](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-F05138.svg?style=flat&logo=swift)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Observation-purple.svg?style=flat)](https://developer.apple.com/xcode/swiftui/)
[![Architecture](https://img.shields.io/badge/Architecture-MVVM%20%2B%20Repository-success.svg?style=flat)](Architecture.md)
[![WidgetKit](https://img.shields.io/badge/Extension-WidgetKit%20%2B%20AppIntents-orange.svg?style=flat)](https://developer.apple.com/widgets/)

An intuitive, modern, production-grade personal expense tracking application built for iOS with **SwiftUI**, **MVVM architecture**, **WidgetKit**, and **App Intents (Siri & Shortcuts)**.

Expense Tracker provides seamless expense logging, live analytics, date-grouped transaction history, offline conference demo modes, interactive iOS Home Screen widgets, and hands-free voice logging through Siri.

---

## 🌟 Key Features

### 1. 📊 Expense Tracking & Categorization
- **Instant Logging**: Quick expense creation with amount, category, custom notes, and date/time selection.
- **Rich Categories**: 6 built-in categories (`Food`, `Transport`, `Shopping`, `Bills`, `Entertainment`, `Other`) with custom SF Symbols and distinctive category color schemes.
- **Multi-Currency Support**: Native currency formatting (defaulting to `EGP`, with support for `USD` and international currencies).
- **Date-Grouped Transaction Stream**: Automatic section grouping by day (*Today*, *Yesterday*, or formatted date), displaying calculated daily subtotals.
- **Swipe-to-Delete**: Smooth swipe actions for expense deletion with automatic timeline updates.

### 2. 📈 Real-Time Analytics & Spending Summaries
- **Gradient Summary Card**: Highlights current monthly spending total and today's total with smooth numeric content transitions (`.contentTransition(.numericText())`).
- **Top Categories Carousel**: Horizontal scrolling pill bar visualizing spending breakdown across top categories.
- **Period Breakdown**: Dynamic backend calculations for daily, weekly, and monthly summaries.

### 3. 📱 WidgetKit & Home Screen Integration
- **Interactive Widgets**:
  - **Small Widget (`.systemSmall`)**: Shows total spending for the selected period (*Today* or *This Month*), period badge, top expense category, and offline status indicator.
  - **Medium Widget (`.systemMedium`)**: Displays total spending, real-time sync state (*Synced* vs *Cached Offline*), and a breakdown of top 3 spending categories with amounts and icons.
- **Configurable Periods**: Configured via `SummaryWidgetConfigurationIntent` (allowing users to toggle between Today and This Month directly from widget settings).
- **Offline Widget Caching**: Utilizes App Group `UserDefaults` (`group.com.workshop.expensetracker`) ensuring widgets display valid data even when disconnected or unauthenticated.

### 4. 🎙️ Siri & App Shortcuts (App Intents)
- **Hands-Free Expense Logging**: Say *"Log an expense in Expense Tracker"* or *"Add a 200 EGP Food expense in Expense Tracker"*.
- **Interactive Siri Dialogue**: Siri prompts for missing amount or category if not specified in the voice command.
- **Visual Snippet Views**: Siri displays custom SwiftUI snippet cards (`AddedExpenseSnippetView` and `ExpenseSummarySnippetView`) inside Siri and Spotlight.
- **Voice Spending Summaries**: Say *"How much did I spend in Expense Tracker"* to hear spoken summary totals and see top spending breakdowns.

### 5. 🔀 Dual Repository Architecture (Live API + Offline Demo Mode)
- **Live REST API Mode**: Communicates with the hosted backend (`https://expensetracker-workshop.runasp.net`) using asynchronous URLSession calls.
- **Conference Demo / Offline Mode**: Instant toggle for offline workshops and presentations via `MockExpenseRepository`. Works completely offline with zero network dependency.
- **Seed Demo Data**: One-tap action to populate realistic sample expenses across different days and categories.

### 6. 🔐 Robust Security & Storage
- **Shared Keychain Access**: Stores JWT Bearer tokens securely across both the main iOS app and the Widget extension via Keychain Access Groups (`$(AppIdentifierPrefix)com.workshop.expensetracker.shared`).
- **Simulator & Graceful Fallbacks**: Transparent fallback mechanisms for development environments where Keychain entitlements differ from physical devices.
- **Sendable Concurrency**: Thread-safe architecture ready for Swift 6 strict concurrency checks.

---

## 🏗️ Architecture & Technology Stack

The project adheres strictly to **SwiftUI MVVM (Model-View-ViewModel)** coupled with the **Repository Pattern**:

```
┌────────────────────────────────────────────────────────┐
│                      UI Layer                          │
│     (HomeView, AuthView, AddExpenseView, Widgets)      │
└───────────────────────────┬────────────────────────────┘
                            │ Observation (@Observable)
┌───────────────────────────▼────────────────────────────┐
│                    ViewModel Layer                     │
│        (HomeViewModel, AuthViewModel, AddExpenseVM)     │
└───────────────────────────┬────────────────────────────┘
                            │ ExpenseRepositoryProtocol
┌───────────────────────────▼────────────────────────────┐
│                   Repository Layer                     │
│       ┌───────────────────────┬──────────────────────┐ │
│       │ LiveExpenseRepository │ MockExpenseRepository│ │
│       └───────────┬───────────┴──────────────────────┘ │
└───────────────────┼────────────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
┌────────▼─────────┐ ┌─────────▼──────────┐
│    APIClient     │ │   SharedStorage    │
│  (REST Service)  │ │(Keychain + AppGroup│
│                  │ │   UserDefaults)    │
└──────────────────┘ └────────────────────┘
```

For complete technical specifications, sequence diagrams, and concurrency design, see **[Architecture.md](Architecture.md)**.

### Technology Stack
- **Frameworks**: SwiftUI, Observation (`@Observable`), WidgetKit, AppIntents, Security, Combine
- **Language**: Swift 5.9+ / Swift 6 Sendable & Concurrency (`async/await`, `@MainActor`, `lock.withLock`)
- **Persistence**: Shared Keychain (`kSecClassGenericPassword`) & App Group `UserDefaults`
- **Networking**: `URLSession` with custom ISO-8601 date decoding (supporting fractional seconds and RFC 3339)

---

## 📁 Project Structure

```text
ExpenseTracker/
├── ExpenseTrackerApp.swift             # App entry point & auth lifecycle listener
├── ContentView.swift                   # Fallback container view
├── AuthView.swift                      # Sign in / registration & offline demo toggle
├── HomeView.swift                      # Primary dashboard: header card & grouped list
├── HomeViewModel.swift                 # Main Actor Observable ViewModel for HomeView
├── AddExpenseView.swift                # Modal sheet to record a new transaction
├── ExpenseIntents.swift                # App Intents & AppShortcutsProvider for Siri
├── ExpenseTracker.entitlements         # App Groups & Keychain Access Groups
│
├── Shared/                             # Shared code accessible by App & Widget target
│   ├── Models/
│   │   └── ExpenseModels.swift         # Expense, ExpenseCategory, Summary, Auth DTOs
│   ├── Networking/
│   │   ├── APIClient.swift             # Network service, URLRequest builder & decoders
│   │   └── Repository/
│   │       └── ExpenseRepository.swift # Protocol, Live & Mock implementations, AppConfig
│   └── Storage/
│       └── SharedStorage.swift         # Shared Keychain & App Group UserDefaults engine
│
├── ExpenseWidget/                      # WidgetKit Extension
│   ├── ExpenseWidgetBundle.swift       # Widget Bundle entry point
│   ├── ExpenseWidget.swift             # Small & Medium Home Screen widgets
│   ├── ExpenseWidgetControl.swift      # Control Center widget
│   ├── ExpenseWidgetLiveActivity.swift # Dynamic Island & Live Activity configuration
│   ├── AppIntent.swift                 # Configuration intents for widgets
│   └── Info.plist
│
├── ExpenseWidgetExtension.entitlements # Widget entitlements (App Group + Keychain)
├── ExpenseTrackerTests/                # Unit test suite
└── ExpenseTrackerUITests/              # UI automation test suite
```

---

## 🌐 API Endpoints Reference

The live service communicates with:
`https://expensetracker-workshop.runasp.net`

| Method | Endpoint | Description | Auth Required |
|:---|:---|:---|:---:|
| `POST` | `/register` | Register a new user with email and password | No |
| `POST` | `/login` | Authenticate and obtain JWT Bearer token | No |
| `GET` | `/expenses` | Retrieve expense list (optional `from`/`to` date filters) | Yes |
| `POST` | `/expenses` | Create a new expense item | Yes |
| `DELETE`| `/expenses/{id}` | Delete an existing expense item by UUID | Yes |
| `GET` | `/summary` | Retrieve total spending and category breakdown | Yes |
| `POST` | `/seed-demo` | Populate sample demo transactions on the backend | Yes |

---

## 🚀 Getting Started

### Prerequisites
- macOS Sonoma (14.0) or later
- Xcode 15.0 or Xcode 16+
- iOS 17.0+ Simulator or physical device

### Building & Running
1. Clone or open the repository folder in Xcode:
   ```bash
   open ExpenseTracker.xcodeproj
   ```
2. Select the **`ExpenseTracker`** scheme.
3. Choose an **iOS 17+ Simulator** (e.g., iPhone 15 Pro / iPhone 16 Pro).
4. Press **⌘ + R** to build and run.

### Running with Demo Data (Offline)
- On the initial launch screen, tap **"Continue with Instant Demo Data"** to immediately explore the app with realistic sample transactions.
- You can toggle **"Offline Mock Mode"** at any time via the top-left ellipsis menu (`...`) in the main navigation bar.

### Adding the Widget
1. Long-press on the Simulator Home Screen until apps jiggle.
2. Tap the **`+`** button in the top-left corner.
3. Search for **"Expense Tracker"**.
4. Choose either the **Small** or **Medium** widget and tap **"Add Widget"**.
5. Long-press the widget and select **"Edit Widget"** to switch the period between *Today* and *This Month*.

---

## 🧪 Testing

Run the test suite using Xcode:
- Press **⌘ + U** to execute unit and UI tests.
- Targets: `ExpenseTrackerTests` and `ExpenseTrackerUITests`.

---

## 📄 License & Credits
Developed by **Abdelrahman Salah** for production iOS expense management and mobile workshops.
Licensed under the [MIT License](LICENSE).
