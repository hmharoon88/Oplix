//
//  ManagerTasksView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ManagerTasksView: View {
    let userId: String
    @StateObject private var viewModel: ManagerTasksViewModel
    @State private var showingAddTask = false
    
    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: ManagerTasksViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Colored Header
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                        Text("Oplix")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            showingAddTask = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),
                                Color(red: 0.15, green: 0.4, blue: 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    
                    // Content Area
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    } else if viewModel.tasks.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "checklist")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.cloudBlue)
                            Text("No tasks yet")
                                .font(.title2)
                                .foregroundColor(Theme.darkGray)
                            Button("Add First Task") {
                                showingAddTask = true
                            }
                            .cloudButton()
                        }
                        .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(viewModel.tasks) { task in
                                ManagerTaskRow(task: task, viewModel: viewModel)
                                    .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                if let index = indexSet.first {
                                    let task = viewModel.tasks[index]
                                    Task {
                                        await viewModel.deleteTask(task)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    
                    // Colored Footer
                    HStack {
                        Spacer()
                        Text("© 2025 Oplix")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),
                                Color(red: 0.15, green: 0.4, blue: 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddTask) {
                AddManagerTaskView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadData()
            }
        }
    }
}

struct ManagerTaskRow: View {
    let task: WorkTask
    @ObservedObject var viewModel: ManagerTasksViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.description)
                .font(.headline)
                .foregroundColor(.black)
            
            if !task.assignedLocationIds.isEmpty {
                let locationNames = task.assignedLocationIds.compactMap { locationId in
                    viewModel.locations.first(where: { $0.id == locationId })?.name
                }
                if !locationNames.isEmpty {
                    Text("Locations: \(locationNames.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundColor(Theme.cloudBlue)
                }
            } else {
                Text("Unassigned")
                    .font(.subheadline)
                    .foregroundColor(Theme.darkGray)
            }
            
            if !task.assignedEmployeeIds.isEmpty {
                let employeeNames = task.assignedEmployeeIds.compactMap { employeeId in
                    viewModel.employees.first(where: { $0.id == employeeId })?.name
                }
                if !employeeNames.isEmpty {
                    Text("Assigned to: \(employeeNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

