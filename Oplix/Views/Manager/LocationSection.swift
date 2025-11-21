//
//  LocationSection.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

enum LocationSection: String, Identifiable, Hashable {
    case employees, tasks, shifts, lottery, documents, payroll, salesExpenses
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .employees: return "Employees"
        case .tasks: return "Tasks"
        case .shifts: return "Shift Manager"
        case .lottery: return "Lottery"
        case .documents: return "Documents"
        case .payroll: return "Payroll"
        case .salesExpenses: return "Sales & Expenses"
        }
    }
    
    var icon: String {
        switch self {
        case .employees: return "person.2.fill"
        case .tasks: return "checklist"
        case .shifts: return "clock.fill"
        case .lottery: return "ticket.fill"
        case .documents: return "doc.fill"
        case .payroll: return "dollarsign.circle.fill"
        case .salesExpenses: return "chart.bar.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .employees: return .blue
        case .tasks: return .green
        case .shifts: return .purple
        case .lottery: return .orange
        case .documents: return .indigo
        case .payroll: return .green
        case .salesExpenses: return .teal
        }
    }
}

