//
//  ExpenseWidgetBundle.swift
//  ExpenseWidget
//
//  Created by Abdelrahman Salah on 07/11/2026.
//

import WidgetKit
import SwiftUI

@main
struct ExpenseWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExpenseWidget()
        ExpenseWidgetControl()
        ExpenseWidgetLiveActivity()
    }
}
