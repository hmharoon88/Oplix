//
//  EmployeesScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct EmployeesScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Binding var showingAddEmployee: Bool
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            List {
                ForEach(viewModel.employees) { employee in
                    NavigationLink(value: employee) {
                        EmployeeRow(employee: employee)
                    }
                    .listRowBackground(Color.clear)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        Task {
                            await viewModel.deleteEmployee(viewModel.employees[index])
                        }
                    }
                }
            }
            .navigationDestination(for: Employee.self) { employee in
                EmployeeDetailView(employee: employee, viewModel: viewModel)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    showingAddEmployee = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Employee")
                    }
                    .frame(maxWidth: .infinity)
                    .cloudButton()
                }
                .padding()
            }
        }
        .navigationTitle("Employees")
        .navigationBarTitleDisplayMode(.large)
    }
}

