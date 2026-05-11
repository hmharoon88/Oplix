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
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var showingSalesExpenses = false
    @State private var recurringPayablesCount = 0
    @State private var recurringReceivablesCount = 0
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
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Error Loading Location")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task {
                            viewModel.resetLoadedDataFlag()
                            await viewModel.loadData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding()
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
                                    count: viewModel.employees.count,
                                    showCount: false
                                )
                            }
                            
                            // Supervisors
                            NavigationLink(value: LocationSection.supervisors) {
                                SectionIconCard(
                                    icon: "person.badge.key.fill",
                                    title: "Supervisors",
                                    color: .purple,
                                    count: viewModel.supervisors.count,
                                    showCount: false
                                )
                            }
                            
                            // Tasks
                            NavigationLink(value: LocationSection.tasks) {
                                SectionIconCard(
                                    icon: "checklist",
                                    title: "Tasks",
                                    color: .green,
                                    count: viewModel.tasks.count,
                                    showCount: false
                                )
                            }
                            
                            // Shifts
                            NavigationLink(value: LocationSection.shifts) {
                                SectionIconCard(
                                    icon: "clock.fill",
                                    title: "Shift Manager",
                                    color: .purple,
                                    count: viewModel.shifts.count,
                                    showCount: false
                                )
                            }
                            
                            // Lottery
                            NavigationLink(value: LocationSection.lottery) {
                                SectionIconCard(
                                    icon: "ticket.fill",
                                    title: "Lottery",
                                    color: .orange,
                                    count: viewModel.lotteryForms.count,
                                    showCount: false
                                )
                            }
                            
                            // Documents
                            NavigationLink(value: LocationSection.documents) {
                                SectionIconCard(
                                    icon: "doc.fill",
                                    title: "Documents",
                                    color: .indigo,
                                    count: 0,
                                    showCount: false
                                )
                            }
                            
                            // Payroll
                            NavigationLink(value: LocationSection.payroll) {
                                SectionIconCard(
                                    icon: "dollarsign.circle.fill",
                                    title: "Payroll",
                                    color: .green,
                                    count: 0,
                                    showCount: false
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
                                    count: 0,
                                    showCount: false
                                )
                            }
                            
                            // Payables
                            NavigationLink(value: LocationSection.payables) {
                                SectionIconCard(
                                    icon: "arrow.up.circle.fill",
                                    title: "Payables",
                                    color: .red,
                                    count: 0,
                                    badgeCount: recurringPayablesCount > 0 ? recurringPayablesCount : nil,
                                    showCount: false
                                )
                            }
                            
                            // Receivables
                            NavigationLink(value: LocationSection.receivables) {
                                SectionIconCard(
                                    icon: "arrow.down.circle.fill",
                                    title: "Receivables",
                                    color: .blue,
                                    count: 0,
                                    badgeCount: recurringReceivablesCount > 0 ? recurringReceivablesCount : nil,
                                    showCount: false
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
            case .supervisors:
                SupervisorsScreen(viewModel: viewModel)
            case .tasks:
                TasksScreen(viewModel: viewModel)
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
            case .payables:
                PayablesView(userId: userId, locationId: locationId)
            case .receivables:
                ReceivablesView(userId: userId, locationId: locationId)
            }
        }
        .onAppear {
            print("🔵 LocationDetailView body rendered")
            Task {
                await loadRecurringCounts()
            }
        }
        .task {
            await loadRecurringCounts()
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
        .task(id: locationId) {
            print("🔵 LocationDetailView task - locationId: \(locationId)")
            // Reset hasLoadedData when locationId changes to allow reloading
            viewModel.resetLoadedDataFlag()
            print("🔵 isLoading: \(viewModel.isLoading)")
            print("🔵 location: \(viewModel.location?.name ?? "nil")")
            print("🔵 Starting loadData...")
            await viewModel.loadData()
            print("🔵 loadData completed - isLoading: \(viewModel.isLoading)")
            print("🔵 location: \(viewModel.location?.name ?? "nil")")
            print("🔵 errorMessage: \(viewModel.errorMessage ?? "nil")")
            viewModel.startObserving()
            print("🔵 Observing started")
            
            // Load statistics
            await statisticsViewModel.loadStatistics(userId: userId, locationId: locationId)
            
            // Load recurring counts for notification badges
            await loadRecurringCounts()
        }
        .onAppear {
            // Also reset when view appears to allow reloading after navigation
            viewModel.resetLoadedDataFlag()
            // Refresh recurring counts when view appears (e.g., returning from payables/receivables)
            Task {
                await loadRecurringCounts()
            }
        }
        .sheet(isPresented: $showingAddEmployee) {
            print("🟡 SHEET - AddEmployeeView PRESENTED")
            print("   Location: \(viewModel.location?.name ?? "nil")")
            print("   LocationId: \(locationId)")
            print("   ViewModel employees count: \(viewModel.employees.count)")
            return AddEmployeeView(viewModel: viewModel)
        }
        .onChange(of: showingAddEmployee) { oldValue, newValue in
            print("🟡 SHEET - showingAddEmployee changed: \(oldValue) -> \(newValue)")
        }
        .sheet(isPresented: $showingSalesExpenses) {
            print("🟡 SHEET - SalesExpensesScreen PRESENTED")
            return SalesExpensesScreen(viewModel: viewModel)
        }
        .onChange(of: showingSalesExpenses) { oldValue, newValue in
            print("🟡 SHEET - showingSalesExpenses changed: \(oldValue) -> \(newValue)")
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
        .task {
            // Load data when view appears
            print("🔵 LocationDetailView - Task: Loading data...")
            viewModel.resetLoadedDataFlag()
            await viewModel.loadData()
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
    
    private func loadRecurringCounts() async {
        do {
            let payables = try await FirebaseService.shared.fetchPayables(userId: userId, locationId: locationId)
            // Only count recurring items that are NOT paid
            recurringPayablesCount = payables.filter { $0.frequency != .none && !$0.isPaid }.count
            
            let receivables = try await FirebaseService.shared.fetchReceivables(userId: userId, locationId: locationId)
            // Only count recurring items that are NOT received
            recurringReceivablesCount = receivables.filter { $0.frequency != .none && !$0.isReceived }.count
        } catch {
            print("Error loading recurring counts: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        LocationDetailView(userId: "test-user", locationId: "test-location")
    }
}
