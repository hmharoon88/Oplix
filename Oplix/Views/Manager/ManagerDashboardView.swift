//
//  ManagerDashboardView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ManagerDashboardView: View {
    /// Bottom chrome for the custom tab bar (shared iPhone + iPad).
    private static let managerTabChromeGradient = LinearGradient(
        colors: [
            Color(red: 0.1, green: 0.3, blue: 0.6),
            Color(red: 0.15, green: 0.4, blue: 0.7)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    @StateObject private var viewModel = ManagerDashboardViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedLocation: Location?
    @State private var locationToDelete: Location?
    @State private var showingDeleteConfirmation = false
    @State private var selectedTab = 2 // Default to Home tab
    @State private var locationRecurringCounts: [String: Int] = [:] // locationId: recurring count
    
    var body: some View {
        // iOS 18+ floating `TabView` leaves a frosted strip over the window
        // that `UITabBarAppearance` cannot fill. Use the same custom bar on
        // all phones and tablets so bottom chrome is always our blue gradient.
        VStack(spacing: 0) {
            mainDashboardContent
            customBottomTabBar
        }
    }

    @ViewBuilder
    private var mainDashboardContent: some View {
        Group {
            switch selectedTab {
            case 0:
                locationsTabContent
            case 1:
                if let userId = authViewModel.currentUser?.id {
                    ManagerEmployeesView(userId: userId)
                }
            case 2:
                if let userId = authViewModel.currentUser?.id {
                    ManagerOverviewView(userId: userId)
                }
            case 3:
                TaskCheckView()
                    .environmentObject(authViewModel)
            case 4:
                SettingsView()
                    .environmentObject(authViewModel)
            default:
                EmptyView()
            }
        }
    }
    private var locationsTabContent: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Colored Header with App Logo
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
                    } else if viewModel.locations.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.cloudBlue)
                            Text("No locations yet")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("Add facilities from the Oplix web dashboard, then sign in here to manage them.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                                Button(action: {
                                    selectedLocation = location
                                }) {
                                    LocationRow(
                                        location: location,
                                        index: index,
                                        userId: authViewModel.currentUser?.id,
                                        recurringCount: locationRecurringCounts[location.id],
                                        todayScore: viewModel.todayScore(for: location),
                                        sevenDayScore: viewModel.sevenDayScore(for: location)
                                    )
                                }
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                if let index = indexSet.first {
                                    locationToDelete = viewModel.locations[index]
                                    showingDeleteConfirmation = true
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.light)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedLocation) { location in
                NavigationStack {
                    if let userId = authViewModel.currentUser?.id {
                        // Built-in Done button (showsCloseButton) replaces
                        // the external toolbar override that used to live here.
                        LocationDetailView(
                            userId: userId,
                            locationId: location.id,
                            showsCloseButton: true
                        )
                        .environmentObject(authViewModel)
                    }
                }
            }
            .alert("Delete Location", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    locationToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let location = locationToDelete {
                        Task {
                            await viewModel.deleteLocation(location)
                            locationToDelete = nil
                        }
                    }
                }
            } message: {
                if let location = locationToDelete {
                    Text("Are you sure you want to delete '\(location.name)'? This action cannot be undone.")
                }
            }
            .task {
                if let userId = authViewModel.currentUser?.id {
                    viewModel.userId = userId
                }
                await viewModel.loadLocations()
                viewModel.startObservingLocations()
                await self.loadRecurringCountsForAllLocations()
            }
        }
    }
    
    private var customBottomTabBar: some View {
        HStack(spacing: 0) {
            // Locations
            tabBarButton(
                icon: "building.2.fill",
                label: "Locations",
                tag: 0,
                isSelected: selectedTab == 0
            )
            
            // Employees
            tabBarButton(
                icon: "person.2.fill",
                label: "Employees",
                tag: 1,
                isSelected: selectedTab == 1
            )
            
            // Home (larger)
            tabBarButton(
                icon: "house.fill",
                label: "Home",
                tag: 2,
                isSelected: selectedTab == 2,
                isLarge: true
            )
            
            // Task Check
            tabBarButton(
                icon: "checkmark.circle.fill",
                label: "Task Check",
                tag: 3,
                isSelected: selectedTab == 3
            )
            
            // Settings
            tabBarButton(
                icon: "gearshape.fill",
                label: "Settings",
                tag: 4,
                isSelected: selectedTab == 4
            )
        }
        .frame(height: 60)
        .background {
            Self.managerTabChromeGradient
                .ignoresSafeArea(edges: .bottom)
        }
    }
    
    private func tabBarButton(icon: String, label: String, tag: Int, isSelected: Bool, isLarge: Bool = false) -> some View {
        Button(action: {
            selectedTab = tag
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isLarge ? 32 : 18, weight: isLarge ? .bold : .regular))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.84, blue: 0.0) : .white.opacity(0.6))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.84, blue: 0.0) : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // Counts recurring items that are actually overdue (frequency != none,
    // still unpaid/unreceived, and past their due-date at start-of-day).
    // The red badge on each LocationRow surfaces this — it should mean
    // "you have stuff to deal with here", not "you have N rows in books".
    private func loadRecurringCountsForAllLocations() async {
        guard let userId = authViewModel.currentUser?.id else { return }
        
        var counts: [String: Int] = [:]
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        for location in viewModel.locations {
            do {
                let payables = try await FirebaseService.shared.fetchPayables(userId: userId, locationId: location.id)
                let receivables = try await FirebaseService.shared.fetchReceivables(userId: userId, locationId: location.id)
                
                let overduePayables = payables.filter { p in
                    guard p.frequency != .none, !p.isPaid, let due = p.dueDate else { return false }
                    return calendar.startOfDay(for: due) < todayStart
                }.count
                let overdueReceivables = receivables.filter { r in
                    guard r.frequency != .none, !r.isReceived, let due = r.dueDate else { return false }
                    return calendar.startOfDay(for: due) < todayStart
                }.count
                
                counts[location.id] = overduePayables + overdueReceivables
            } catch {
                print("Error loading recurring counts for location \(location.id): \(error.localizedDescription)")
            }
        }
        
        locationRecurringCounts = counts
    }
}

struct LocationRow: View {
    let location: Location
    let index: Int
    let userId: String?
    // Count of OVERDUE recurring payables + receivables for this location.
    // Surfaced as a red badge next to the location name. nil hides the badge.
    let recurringCount: Int?
    // Optional today + 7-day completion scores. When non-nil, a thin
    // progress bar is drawn at the bottom of the card. Pass nil to keep
    // the existing legacy appearance.
    var todayScore: LocationScoreSegment? = nil
    var sevenDayScore: LocationScoreSegment? = nil

    private var cardGradient: LinearGradient {
        // More vibrant and colorful gradients with multiple colors
        let gradients: [[Color]] = [
            // Blue to Purple to Pink
            [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 1.0), Color(red: 1.0, green: 0.4, blue: 0.8)],
            // Orange to Red to Pink
            [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.7)],
            // Green to Cyan to Blue
            [Color(red: 0.2, green: 0.9, blue: 0.5), Color(red: 0.2, green: 0.8, blue: 1.0), Color(red: 0.3, green: 0.5, blue: 1.0)],
            // Yellow to Orange to Red
            [Color(red: 1.0, green: 0.9, blue: 0.2), Color(red: 1.0, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.3)],
            // Purple to Blue to Cyan
            [Color(red: 0.7, green: 0.3, blue: 1.0), Color(red: 0.3, green: 0.5, blue: 1.0), Color(red: 0.2, green: 0.8, blue: 1.0)],
            // Pink to Purple to Blue
            [Color(red: 1.0, green: 0.4, blue: 0.8), Color(red: 0.8, green: 0.3, blue: 1.0), Color(red: 0.4, green: 0.5, blue: 1.0)],
            // Cyan to Green to Yellow
            [Color(red: 0.2, green: 0.9, blue: 1.0), Color(red: 0.3, green: 1.0, blue: 0.5), Color(red: 0.9, green: 1.0, blue: 0.3)],
            // Red to Orange to Yellow
            [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.2), Color(red: 1.0, green: 0.8, blue: 0.2)],
        ]
        let gradientColors = gradients[index % gradients.count]
        return LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(location.name)
                            .font(.headline)
                            .foregroundColor(.white)
                            .fontWeight(.bold)

                        if let recurringCount = recurringCount, recurringCount > 0 {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Text("\(recurringCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }

                    Text(location.address)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.95))
                }
                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.9))
                    .fontWeight(.semibold)
                    .font(.system(size: 16))
            }

            // Score bar — only rendered when at least one segment is supplied.
            if todayScore != nil || sevenDayScore != nil {
                scoreBar
            }
        }
        .padding()
        .background(cardGradient)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
    }

    // White-on-gradient progress bar that shows two stacked tracks:
    // "TODAY" (filled to today's %) and "PAST WEEK" (filled to the previous
    // 7 full days' completion rate), with a small label on the right showing
    // both percentages.
    private var scoreBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let today = todayScore {
                scoreTrack(label: "TODAY", segment: today)
            }
            if let week = sevenDayScore {
                scoreTrack(label: "PAST WEEK", segment: week)
            }
        }
        .padding(.top, 4)
    }

    private func scoreTrack(label: String, segment: LocationScoreSegment) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(4, geo.size.width * segment.percentage))
                }
            }
            .frame(height: 6)

            Text("\(segment.numerator)/\(segment.denominator) · \(segment.displayPercent)%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 86, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

#Preview {
    ManagerDashboardView()
        .environmentObject(AuthViewModel())
}
