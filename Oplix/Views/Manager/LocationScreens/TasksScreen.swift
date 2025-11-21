//
//  TasksScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct TasksScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Binding var showingAddTask: Bool
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            List {
                ForEach(viewModel.tasks) { task in
                    TaskRow(task: task, viewModel: viewModel)
                        .listRowBackground(Color.clear)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        Task {
                            await viewModel.deleteTask(viewModel.tasks[index])
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    showingAddTask = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Task")
                    }
                    .frame(maxWidth: .infinity)
                    .cloudButton()
                }
                .padding()
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.large)
    }
}

