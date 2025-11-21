//
//  LocationDetailView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LocationDetailView: View {
    let userId: String
    let locationId: String
    @StateObject private var viewModel: LocationDetailViewModel
    @StateObject private var statisticsViewModel = LocationStatisticsViewModel()
    @State private var showingAddEmployee = false
    @State private var showingAddTask = false
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var showingSalesExpenses = false
    @Environment(\.dismiss) var dismiss
    
    init(userId: String, locationId: String) {
        self.userId = userId
        self.locationId = locationId
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: userId, locationId: locationId))
        print("🔵 LocationDetailView init - userId: \(userId), locationId: \(locationId)")
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Theme.cloudBlue)
                    Text("Loading location...")
                        .foregroundColor(.primary)
                        .font(.headline)
                    Text("ID: \(locationId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    print("🔵 Showing loading state")
                }
            } else if let location = viewModel.location {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(location.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(location.address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.cloudWhite)
                    
                    // Statistics Section
                    VStack(spacing: 0) {
                        if statisticsViewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Text("Loading statistics...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 16)
                        } else {
                            HStack(spacing: 20) {
                                // Total Employees
                                VStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    Text("\(statisticsViewModel.totalEmployees)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("Employees")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                
                                Divider()
                                    .frame(height: 50)
                                
                                // Total Hours
                                VStack(spacing: 8) {
                                    Image(systemName: "clock.fill")
                                        .font(.title2)
                                        .foregroundColor(.purple)
                                    Text(String(format: "%.1f", statisticsViewModel.totalHours))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("Total Hours")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                
                                Divider()
                                    .frame(height: 50)
                                
                                // Total Payout
                                VStack(spacing: 8) {
                                    Image(systemName: "dollarsign.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                    Text(formatCurrency(statisticsViewModel.totalPayout))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("Total Payout")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal)
                        }
                    }
                    .background(Theme.cloudWhite)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color.gray.opacity(0.2)),
                        alignment: .bottom
                    )
                    
                    // Icon buttons grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 20),
                            GridItem(.flexible(), spacing: 20)
                        ], spacing: 30) {
                            // Employees
                            NavigationLink(value: LocationSection.employees) {
                                SectionIconCard(
                                    icon: "person.2.fill",
                                    title: "Employees",
                                    color: .blue,
                                    count: viewModel.employees.count
                                )
                            }
                            
                            // Tasks
                            NavigationLink(value: LocationSection.tasks) {
                                SectionIconCard(
                                    icon: "checklist",
                                    title: "Tasks",
                                    color: .green,
                                    count: viewModel.tasks.count
                                )
                            }
                            
                            // Shifts
                            NavigationLink(value: LocationSection.shifts) {
                                SectionIconCard(
                                    icon: "clock.fill",
                                    title: "Shift Manager",
                                    color: .purple,
                                    count: viewModel.shifts.count
                                )
                            }
                            
                            // Lottery
                            NavigationLink(value: LocationSection.lottery) {
                                SectionIconCard(
                                    icon: "ticket.fill",
                                    title: "Lottery",
                                    color: .orange,
                                    count: viewModel.lotteryForms.count
                                )
                            }
                            
                            // Documents
                            NavigationLink(value: LocationSection.documents) {
                                SectionIconCard(
                                    icon: "doc.fill",
                                    title: "Documents",
                                    color: .indigo,
                                    count: 0
                                )
                            }
                            
                            // Payroll
                            NavigationLink(value: LocationSection.payroll) {
                                SectionIconCard(
                                    icon: "dollarsign.circle.fill",
                                    title: "Payroll",
                                    color: .green,
                                    count: 0
                                )
                            }
                            
                            // Sales & Expenses
                            Button(action: {
                                showingSalesExpenses = true
                            }) {
                                SectionIconCard(
                                    icon: "chart.bar.fill",
                                    title: "Sales & Expenses",
                                    color: .teal,
                                    count: 0
                                )
                            }
                        }
                        .padding()
                    }
                }
                .onAppear {
                    print("🔵 Showing location content - \(location.name)")
                }
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Error Loading Location")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task {
                            await viewModel.loadData()
                        }
                    }
                    .cloudButton()
                }
                .padding()
                .onAppear {
                    print("🔵 Showing error state - \(errorMessage)")
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                    Text("Location Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("The location could not be loaded.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                    Text("Location ID: \(locationId)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Button("Retry") {
                        Task {
                            await viewModel.loadData()
                        }
                    }
                    .cloudButton()
                }
                .padding()
                .onAppear {
                    print("🔵 Showing 'not found' state")
                }
            }
        }
        .navigationDestination(for: LocationSection.self) { section in
            switch section {
            case .employees:
                EmployeesScreen(viewModel: viewModel, showingAddEmployee: $showingAddEmployee)
            case .tasks:
                TasksScreen(viewModel: viewModel, showingAddTask: $showingAddTask)
            case .shifts:
                ShiftsScreen(viewModel: viewModel)
            case .lottery:
                LotteryScreen(viewModel: viewModel)
            case .documents:
                DocumentsScreen(viewModel: viewModel)
            case .payroll:
                PayrollScreen(viewModel: viewModel)
            case .salesExpenses:
                // Sales & Expenses is handled via sheet, not navigation
                EmptyView()
            }
        }
        .onAppear {
            print("🔵 LocationDetailView body rendered")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(viewModel.location?.name ?? "Location")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            print("🔵 LocationDetailView onAppear - locationId: \(locationId)")
            print("🔵 isLoading: \(viewModel.isLoading)")
            print("🔵 location: \(viewModel.location?.name ?? "nil")")
            Task {
                print("🔵 Starting loadData...")
                await viewModel.loadData()
                print("🔵 loadData completed - isLoading: \(viewModel.isLoading)")
                print("🔵 location: \(viewModel.location?.name ?? "nil")")
                print("🔵 errorMessage: \(viewModel.errorMessage ?? "nil")")
                viewModel.startObserving()
                print("🔵 Observing started")
                
                // Load statistics
                await statisticsViewModel.loadStatistics(userId: userId, locationId: locationId)
            }
        }
        .sheet(isPresented: $showingAddEmployee) {
            AddEmployeeView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSalesExpenses) {
            SalesExpensesScreen(viewModel: viewModel)
        }
        .alert("Delete Location", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteLocation()
                }
            }
        } message: {
            if let location = viewModel.location {
                Text("Are you sure you want to delete '\(location.name)'? This action cannot be undone.")
            }
        }
        .onChange(of: viewModel.errorMessage) { oldValue, newValue in
            showingError = newValue != nil
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private func deleteLocation() async {
        guard let location = viewModel.location else {
            viewModel.errorMessage = "Location not found"
            return
        }
        
        print("🔴 Starting location deletion - userId: \(userId), locationId: \(location.id)")
        
        do {
            print("🔴 Calling FirebaseService.deleteLocation...")
            try await FirebaseService.shared.deleteLocation(userId: userId, locationId: location.id)
            print("🔴 Location deleted successfully, dismissing view...")
            
            // Small delay to ensure Firestore updates propagate
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                dismiss()
            }
        } catch {
            print("🔴 Error deleting location: \(error.localizedDescription)")
            print("🔴 Error details: \(error)")
            viewModel.errorMessage = "Failed to delete location: \(error.localizedDescription)"
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

#Preview {
    NavigationStack {
        LocationDetailView(userId: "test-user", locationId: "test-location")
    }
}
