//
//  LocationSection.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

enum LocationSection: String, Identifiable, Hashable {
    case employees, supervisors, tasks, shifts, lottery, documents, payroll, salesExpenses, payables, receivables
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .employees: return "Employees"
        case .supervisors: return "Supervisors"
        case .tasks: return "Tasks"
        case .shifts: return "Shift Manager"
        case .lottery: return "Lottery"
        case .documents: return "Documents"
        case .payroll: return "Payroll"
        case .salesExpenses: return "Sales & Expenses"
        case .payables: return "Payables"
        case .receivables: return "Receivables"
        }
    }
    
    var icon: String {
        switch self {
        case .employees: return "person.2.fill"
        case .supervisors: return "person.badge.key.fill"
        case .tasks: return "checklist"
        case .shifts: return "clock.fill"
        case .lottery: return "ticket.fill"
        case .documents: return "doc.fill"
        case .payroll: return "dollarsign.circle.fill"
        case .salesExpenses: return "chart.bar.fill"
        case .payables: return "arrow.up.circle.fill"
        case .receivables: return "arrow.down.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .employees: return .blue
        case .supervisors: return .purple
        case .tasks: return .green
        case .shifts: return .purple
        case .lottery: return .orange
        case .documents: return .indigo
        case .payroll: return .green
        case .salesExpenses: return .teal
        case .payables: return .red
        case .receivables: return .blue
        }
    }
}

