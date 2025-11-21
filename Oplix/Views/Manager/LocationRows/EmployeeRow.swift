//
//  EmployeeRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct EmployeeRow: View {
    let employee: Employee
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(employee.name)
                    .font(.headline)
                Text(employee.username)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(employee.currentShiftStatus.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(employee.currentShiftStatus == .clockedIn ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
        .cloudCard()
    }
}

