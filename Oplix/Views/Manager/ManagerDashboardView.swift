//
//  ManagerDashboardView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct ManagerDashboardView: View {
    @StateObject private var viewModel = ManagerDashboardViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingAddLocation = false
    @State private var selectedLocation: Location?
    @State private var locationToDelete: Location?
    @State private var showingDeleteConfirmation = false
    @State private var selectedTab = 2 // Default to Home tab
    @State private var locationRecurringCounts: [String: Int] = [:] // locationId: recurring count
    
    var body: some View {
        ZStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad: Use custom layout with bottom bar
                VStack(spacing: 0) {
                    // Content
                    Group {
                        if selectedTab == 0 {
                            locationsTabContent
                        } else if selectedTab == 1, let userId = authViewModel.currentUser?.id {
                            ManagerEmployeesView(userId: userId)
                        } else if selectedTab == 2, let userId = authViewModel.currentUser?.id {
                            ManagerOverviewView(userId: userId)
                        } else if selectedTab == 3 {
                            TaskCheckView()
                                .environmentObject(authViewModel)
                        } else if selectedTab == 4 {
                            SettingsView()
                                .environmentObject(authViewModel)
                        }
                    }
                    
                    // Custom bottom tab bar
                    customBottomTabBar
                }
            } else {
                // iPhone: Use standard TabView
                standardTabView
            }
        }
        .onAppear {
            // Set tab bar appearance for the entire app
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
            
            // Set icon and text colors
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.6)]
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)]
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            UITabBar.appearance().barTintColor = UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
            UITabBar.appearance().isTranslucent = false
        }
    }
    
    private var standardTabView: some View {
        TabView(selection: $selectedTab) {
            // Locations Tab
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
                            Button(action: {
                                showingAddLocation = true
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
                                    Color(red: 0.1, green: 0.3, blue: 0.6),  // Dark blue
                                    Color(red: 0.15, green: 0.4, blue: 0.7)   // Medium dark blue
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
                                Button("Add First Location") {
                                    showingAddLocation = true
                                }
                                .cloudButton()
                            }
                            .padding()
                            Spacer()
                        } else {
                            List {
                                ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                                    Button(action: {
                                        print("🟡 Tapped location: \(location.name) (ID: \(location.id))")
                                        selectedLocation = location
                                        print("🟡 selectedLocation set to: \(selectedLocation?.name ?? "nil")")
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
                .onAppear {
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithTransparentBackground()
                    appearance.backgroundColor = UIColor.clear
                    appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.clear]
                    appearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
                    UINavigationBar.appearance().standardAppearance = appearance
                    UINavigationBar.appearance().scrollEdgeAppearance = appearance
                    
                    Task {
                        await self.loadRecurringCountsForAllLocations()
                    }
                }
                .task {
                    await self.loadRecurringCountsForAllLocations()
                }
                .toolbar {
                    // Add button is now in the header
                }
                .sheet(isPresented: $showingAddLocation) {
                    print("🟡 SHEET - AddLocationView PRESENTED (from ManagerDashboard)")
                    return AddLocationView(viewModel: viewModel)
                        .environmentObject(authViewModel)
                }
                .onChange(of: showingAddLocation) { oldValue, newValue in
                    print("🟡 SHEET - showingAddLocation changed: \(oldValue) -> \(newValue)")
                }
                .fullScreenCover(item: $selectedLocation) { location in
                    NavigationStack {
                        Group {
                            if let userId = authViewModel.currentUser?.id {
                                LocationDetailView(userId: userId, locationId: location.id)
                            } else {
                                Text("Error: User not authenticated")
                            }
                        }
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    print("🟡 Done button tapped")
                                    selectedLocation = nil
                                }
                            }
                        }
                        .onAppear {
                            print("🟡 fullScreenCover presenting - location: \(location.name)")
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
                    // Set userId from authenticated user
                    if let userId = authViewModel.currentUser?.id {
                        viewModel.userId = userId
                    }
                    await viewModel.loadLocations()
                    viewModel.startObservingLocations()
                }
            }
            .tabItem {
                Label("Locations", systemImage: "building.2.fill")
            }
            .tag(0)
            
            // Employees Tab
            if let userId = authViewModel.currentUser?.id {
                ManagerEmployeesView(userId: userId)
                    .tabItem {
                        Label("Employees", systemImage: "person.2.fill")
                    }
                    .tag(1)
            }
            
            // Home Tab (Overview) - Center position with larger icon
            if let userId = authViewModel.currentUser?.id {
                ManagerOverviewView(userId: userId)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(2)
            }
            
            // Task Check Tab
            TaskCheckView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label("Task Check", systemImage: "checkmark.circle.fill")
                }
                .tag(3)
            
            // Settings Tab
            SettingsView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .onAppear {
            // Set tab bar appearance to make icons white with dark blue background
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            
            // Dark blue background matching the header/footer
            appearance.backgroundColor = UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
            
            // Set unselected icon color to white with reduced opacity
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.6)]
            
            // Set selected icon color to bright yellow/gold for visibility
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Gold/Yellow
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)]
            
            // Apply to both standard and scroll edge appearances
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            
            // Also set the background color directly
            UITabBar.appearance().barTintColor = UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
            UITabBar.appearance().isTranslucent = false
            
            // Make Home tab icon bigger and others smaller
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    var tabBarController: UITabBarController?
                    
                    // Find tab bar controller
                    if let root = window.rootViewController as? UITabBarController {
                        tabBarController = root
                    } else if let nav = window.rootViewController as? UINavigationController,
                              let tab = nav.viewControllers.first as? UITabBarController {
                        tabBarController = tab
                    } else {
                        // Search in children
                        func findTabBarController(in viewController: UIViewController) -> UITabBarController? {
                            if let tab = viewController as? UITabBarController {
                                return tab
                            }
                            for child in viewController.children {
                                if let tab = findTabBarController(in: child) {
                                    return tab
                                }
                            }
                            return nil
                        }
                        if let root = window.rootViewController {
                            tabBarController = findTabBarController(in: root)
                        }
                    }
                    
                    guard let tabBarController = tabBarController,
                          let tabBarItems = tabBarController.tabBar.items else { return }
                    
                    // Apply appearance to the actual tab bar
                    tabBarController.tabBar.standardAppearance = appearance
                    tabBarController.tabBar.scrollEdgeAppearance = appearance
                    tabBarController.tabBar.barTintColor = UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
                    tabBarController.tabBar.isTranslucent = false
                    
                    // Make other icons smaller (pointSize 18)
                    for (index, item) in tabBarItems.enumerated() where index != 2 {
                        if let image = item.image {
                            item.image = image.withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
                        }
                        if let selectedImage = item.selectedImage {
                            item.selectedImage = selectedImage.withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
                        }
                    }
                    
                    // Make Home tab icon bigger (index 2, pointSize 32)
                    if tabBarItems.count > 2 {
                        let homeItem = tabBarItems[2]
                        homeItem.image = UIImage(systemName: "house.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 32, weight: .bold))
                        homeItem.selectedImage = UIImage(systemName: "house.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 32, weight: .bold))
                    }
                }
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
                        Button(action: {
                            showingAddLocation = true
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
                    } else if viewModel.locations.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.cloudBlue)
                            Text("No locations yet")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Button("Add First Location") {
                                showingAddLocation = true
                            }
                            .cloudButton()
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
            .sheet(isPresented: $showingAddLocation) {
                AddLocationView(viewModel: viewModel)
                    .environmentObject(authViewModel)
            }
            .fullScreenCover(item: $selectedLocation) { location in
                NavigationStack {
                    if let userId = authViewModel.currentUser?.id {
                        LocationDetailView(userId: userId, locationId: location.id)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") {
                                        selectedLocation = nil
                                    }
                                }
                            }
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
    
    private func loadRecurringCountsForAllLocations() async {
        guard let userId = authViewModel.currentUser?.id else { return }
        
        var counts: [String: Int] = [:]
        
        for location in viewModel.locations {
            do {
                let payables = try await FirebaseService.shared.fetchPayables(userId: userId, locationId: location.id)
                let receivables = try await FirebaseService.shared.fetchReceivables(userId: userId, locationId: location.id)
                
                let recurringPayables = payables.filter { $0.frequency != .none }.count
                let recurringReceivables = receivables.filter { $0.frequency != .none }.count
                
                counts[location.id] = recurringPayables + recurringReceivables
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
    let recurringCount: Int? // Optional recurring items count for badge
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

// Helper view to force tab bar to bottom on iPad
struct TabBarPositionFix: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                findAndFixTabBar(in: window.rootViewController)
            }
        }
    }
    
    private func findAndFixTabBar(in viewController: UIViewController?) {
        guard let viewController = viewController else { return }
        
        if let tabBarController = viewController as? UITabBarController {
            // Force tab bar to bottom on iPad
            if UIDevice.current.userInterfaceIdiom == .pad {
                tabBarController.tabBar.isHidden = false
                // Ensure tab bar is at bottom
                tabBarController.view.setNeedsLayout()
                tabBarController.view.layoutIfNeeded()
            }
        }
        
        // Recursively check children
        for child in viewController.children {
            findAndFixTabBar(in: child)
        }
        
        // Check presented view controllers
        if let presented = viewController.presentedViewController {
            findAndFixTabBar(in: presented)
        }
    }
}

#Preview {
    ManagerDashboardView()
        .environmentObject(AuthViewModel())
}
