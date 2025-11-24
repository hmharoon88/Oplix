//
//  ManagerOverviewView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ManagerOverviewView: View {
    let userId: String
    @StateObject private var viewModel: ManagerOverviewViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedLocation: Location?
    
    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: ManagerOverviewViewModel(userId: userId))
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
                    
                    // Content
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                // Header
                                VStack(spacing: 8) {
                                    Image(systemName: "cloud.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(Theme.cloudBlue)
                                    Text(viewModel.organizationName ?? "Overview")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("Quick summary of your data")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 20)
                                
                                // Expiring Documents Notification
                                if !viewModel.expiringDocuments.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text("Documents Expiring Soon")
                                                .font(.headline)
                                                .foregroundColor(.black)
                                            Spacer()
                                        }
                                        
                                        ForEach(viewModel.expiringDocuments) { document in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(document.name)
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.black)
                                                    
                                                    if let location = viewModel.locations.first(where: { $0.id == document.locationId }) {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "mappin.circle.fill")
                                                                .font(.caption2)
                                                                .foregroundColor(Theme.cloudBlue)
                                                            Text("Location: \(location.name)")
                                                                .font(.caption)
                                                                .foregroundColor(.black)
                                                        }
                                                    }
                                                    
                                                    if let expiryDate = document.expiryDate {
                                                        Text("Expires: \(formatDate(expiryDate))")
                                                            .font(.caption)
                                                            .foregroundColor(.black)
                                                    }
                                                }
                                                
                                                Spacer()
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                }
                                
                                // Statistics Cards
                                VStack(spacing: 16) {
                                    StatCard(
                                        icon: "building.2.fill",
                                        title: "\(viewModel.totalLocations) location\(viewModel.totalLocations == 1 ? "" : "s")",
                                        value: nil,
                                        color: .blue
                                    )
                                    
                                    StatCard(
                                        icon: "person.2.fill",
                                        title: "\(viewModel.totalEmployees) Employee\(viewModel.totalEmployees == 1 ? "" : "s")",
                                        value: nil,
                                        color: .green
                                    )
                                    
                                    StatCard(
                                        icon: "checklist",
                                        title: "\(viewModel.totalTasks) Task\(viewModel.totalTasks == 1 ? "" : "s")",
                                        value: nil,
                                        color: .orange
                                    )
                                }
                                .padding(.horizontal)
                                
                                // Location-specific stats
                                if !viewModel.locationStats.isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text("Month to Date")
                                            .font(.headline)
                                            .foregroundColor(.black)
                                            .padding(.horizontal)
                                        
                                        ForEach(viewModel.locationStats) { stat in
                                            LocationStatsCard(stats: stat)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                                
                                // Stats By Month Section
                                if !viewModel.locations.isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text("Stats By Month")
                                            .font(.headline)
                                            .foregroundColor(.black)
                                            .padding(.horizontal)
                                        
                                        ForEach(viewModel.locations) { location in
                                            Button(action: {
                                                selectedLocation = location
                                            }) {
                                                LocationCard(location: location)
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                                
                                if let errorMessage = viewModel.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding()
                                }
                            }
                            .padding(.vertical)
                        }
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
            .onAppear {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = UIColor.clear
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.clear]
                appearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
            .task {
                await viewModel.loadOverview()
            }
            .fullScreenCover(item: $selectedLocation) { location in
                LocationMonthlyStatsView(
                    userId: userId,
                    locationId: location.id,
                    locationName: location.name
                )
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct LocationCard: View {
    let location: Location
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                    .foregroundColor(.black)
                Text(location.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String?
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(
                        colors: [color.opacity(0.8), color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
            
            if let value = value {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.black)
                }
            } else {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.black)
            }
            
            Spacer()
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct LocationStatsCard: View {
    let stats: LocationStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Location Name Header
            Text(stats.locationName)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            // Stats
            VStack(spacing: 8) {
                StatRow(
                    icon: "dollarsign.circle.fill",
                    label: "Sales",
                    value: formatCurrency(stats.monthToDateSales),
                    color: .blue
                )
                
                StatRow(
                    icon: "ticket.fill",
                    label: "Lottery Sales",
                    value: formatCurrency(stats.monthToDateLotterySales),
                    color: .purple
                )
                
                StatRow(
                    icon: "banknote.fill",
                    label: "Payroll",
                    value: formatCurrency(stats.monthToDatePayroll),
                    color: .green
                )
                
                StatRow(
                    icon: "arrow.down.circle.fill",
                    label: "Expenses",
                    value: formatCurrency(stats.monthToDateExpenses),
                    color: .red
                )
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
        }
    }
}

#Preview {
    ManagerOverviewView(userId: "test-user")
}

