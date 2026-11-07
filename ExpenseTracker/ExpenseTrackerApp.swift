//
//  ExpenseTrackerApp.swift
//  ExpenseTracker
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import SwiftUI
import AppIntents

@main
struct ExpenseTrackerApp: App {
    @State private var isAuthenticated: Bool = SharedStorage.shared.isAuthenticated

    init() {
        ExpenseShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    HomeView()
                } else {
                    AuthView {
                        isAuthenticated = true
                    }
                }
            }
            .animation(.snappy, value: isAuthenticated)
            .onReceive(NotificationCenter.default.publisher(for: .authStateDidChange)) { _ in
                isAuthenticated = SharedStorage.shared.isAuthenticated
            }
        }
    }
}
