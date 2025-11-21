//
//  TaskRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct TaskRow: View {
    let task: WorkTask
    @ObservedObject var viewModel: LocationDetailViewModel
    
    var body: some View {
        HStack {
            Button(action: {
                var updatedTask = task
                updatedTask.isCompleted.toggle()
                Task {
                    await viewModel.updateTask(updatedTask)
                }
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.description)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                if let employeeId = task.assignedToEmployeeId {
                    Text("Assigned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .cloudCard()
    }
}

