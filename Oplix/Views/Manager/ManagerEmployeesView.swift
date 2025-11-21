//
//  ManagerEmployeesView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ManagerEmployeesView: View {
    let userId: String
    @StateObject private var viewModel: ManagerEmployeesViewModel
    @State private var showingAddEmployee = false
    
    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: ManagerEmployeesViewModel(userId: userId))
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
                            showingAddEmployee = true
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
                    } else if viewModel.employees.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.cloudBlue)
                            Text("No employees yet")
                                .font(.title2)
                                .foregroundColor(Theme.darkGray)
                            Button("Add First Employee") {
                                showingAddEmployee = true
                            }
                            .cloudButton()
                        }
                        .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(viewModel.employees) { employee in
                                ManagerEmployeeRow(employee: employee, viewModel: viewModel)
                                    .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                if let index = indexSet.first {
                                    let employee = viewModel.employees[index]
                                    Task {
                                        await viewModel.deleteEmployee(employee)
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
            .sheet(isPresented: $showingAddEmployee) {
                AddManagerEmployeeView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadData()
            }
        }
    }
}

struct ManagerEmployeeRow: View {
    let employee: Employee
    @ObservedObject var viewModel: ManagerEmployeesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(employee.name)
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                if !employee.assignedLocationIds.isEmpty {
                    Text("\(employee.assignedLocationIds.count) location\(employee.assignedLocationIds.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(Theme.cloudBlue)
                } else {
                    Text("Unassigned")
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                }
            }
            
            Text("Username: \(employee.username)")
                .font(.subheadline)
                .foregroundColor(Theme.darkGray)
            
            if !employee.assignedLocationIds.isEmpty {
                let locationNames = employee.assignedLocationIds.compactMap { locationId in
                    viewModel.locations.first(where: { $0.id == locationId })?.name
                }
                if !locationNames.isEmpty {
                    Text("Locations: \(locationNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(Theme.cloudBlue)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

