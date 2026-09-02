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
    @State private var employeeToDelete: Employee?
    @State private var showingDeleteConfirmation = false
    
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
                            Text("Add employees from a location")
                                .font(.subheadline)
                                .foregroundColor(Theme.darkGray)
                        }
                        .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(viewModel.employeeSections) { section in
                                Section {
                                    ForEach(section.employees) { employee in
                                        NavigationLink(value: employee) {
                                            ManagerEmployeeRow(employee: employee, viewModel: viewModel)
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                employeeToDelete = employee
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                } header: {
                                    Text(section.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(Theme.darkGray)
                                        .textCase(nil)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .navigationDestination(for: Employee.self) { employee in
                            EditManagerEmployeeView(employee: employee, viewModel: viewModel)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete Employee", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    employeeToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let employee = employeeToDelete {
                        Task {
                            await viewModel.deleteEmployee(employee)
                            employeeToDelete = nil
                        }
                    }
                }
            } message: {
                if let employee = employeeToDelete {
                    Text("Delete \(employee.name)? This removes their login and all facility assignments. This cannot be undone.")
                }
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

    private var progress: (completed: Int, assigned: Int)? {
        guard !viewModel.tasks.isEmpty else { return nil }
        let result = TaskProgress.employeeToday(tasks: viewModel.tasks, employeeId: employee.id)
        guard result.assigned > 0 else { return nil }
        return result
    }

    /// Resolved role from the view model's role cache. Until the role
    /// fetch completes we suppress the chip rather than guessing
    /// `.employee`, which would briefly mislabel actual supervisors.
    private var resolvedRole: User.UserRole? {
        viewModel.userRoles[employee.id]
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(employee.name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .lineLimit(1)
            if let role = resolvedRole {
                roleChip(for: role)
            }
            Spacer(minLength: 4)
            if let rate = employee.hourlyRate {
                Text("\(formatHourlyRate(rate))/hr")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Theme.darkGray)
            }
            if let progress = progress {
                taskProgressBadge(completed: progress.completed, total: progress.assigned)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cloudWhite)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    private func formatHourlyRate(_ rate: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = rate.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: rate)) ?? String(format: "$%.2f", rate)
    }

    /// Small inline pill that surfaces the employee's User.role next to
    /// their name. Supervisors get a distinct teal accent so they're
    /// scannable in a long list; regular employees get a low-contrast
    /// chip so the name stays the visual anchor.
    @ViewBuilder
    private func roleChip(for role: User.UserRole) -> some View {
        let isSupervisor = role == .supervisor
        let color: Color = isSupervisor ? .teal : Theme.darkGray
        let label = isSupervisor ? "Supervisor" : "Employee"
        let icon = isSupervisor ? "star.fill" : "person.fill"

        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func taskProgressBadge(completed: Int, total: Int) -> some View {
        let isDone = completed == total
        let isPartial = completed > 0 && completed < total
        let color: Color = isDone ? .green : (isPartial ? .orange : .gray)

        HStack(spacing: 4) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "checklist")
                .font(.system(size: 11, weight: .semibold))
            Text("\(completed)/\(total)")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }
}

