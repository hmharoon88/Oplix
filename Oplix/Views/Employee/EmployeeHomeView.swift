//
//  EmployeeHomeView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

/// Top-level shell for the employee/supervisor experience.
///
/// Responsibilities:
///   1. Resolve the list of locations the user is allowed to access
///      (their `Employee.assignedLocationIds`).
///   2. If they're assigned to a single location, route straight in.
///   3. If they're assigned to ≥ 2 locations, present `LocationPickerView`
///      every launch — per product decision, the user must explicitly
///      choose each session so it's never ambiguous which location they're
///      operating against.
///   4. Inject a `requestLocationSwitch` closure into the environment so
///      deeper screens (e.g. SupervisorControlsView) can put the shell
///      back into the picker mid-session.
///
/// The actual rendering of the home screen lives in `EmployeeHomeContent`,
/// which is keyed by `locationId` via `.id(...)` so a switch fully
/// recreates the per-location view-model instead of mutating it in place.
struct EmployeeHomeView: View {
    let user: User
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var assignedLocations: [Location] = []
    @State private var activeLocationId: String?
    @State private var isResolving = true
    @State private var resolveError: String?

    var body: some View {
        Group {
            if isResolving {
                resolvingView
            } else if let resolveError {
                LocationResolveErrorView(
                    message: resolveError,
                    onRetry: { Task { await resolveLocations() } },
                    onLogout: { authViewModel.signOut() }
                )
            } else if let activeLocationId, assignedLocations.contains(where: { $0.id == activeLocationId }) {
                EmployeeHomeContent(user: user, locationId: activeLocationId)
                    // Recreate the entire content + view-model when the
                    // active location changes — much cleaner than trying
                    // to mutate the existing view-model's locationId in
                    // place, which would risk stale Firestore listeners.
                    .id(activeLocationId)
                    .environment(
                        \.requestLocationSwitch,
                        // Only expose the in-session switch action when
                        // there's actually somewhere to switch to.
                        assignedLocations.count >= 2
                            ? { self.activeLocationId = nil }
                            : nil
                    )
            } else {
                LocationPickerView(
                    userName: user.username,
                    userRoleLabel: roleLabel,
                    locations: assignedLocations,
                    preselectedLocationId: user.locationId,
                    onSelect: { activeLocationId = $0 },
                    onLogout: { authViewModel.signOut() }
                )
            }
        }
        .task {
            await resolveLocations()
        }
    }

    private var resolvingView: some View {
        ZStack {
            Theme.secondaryGradient.ignoresSafeArea()
            ProgressView("Loading…")
                .tint(Theme.cloudBlue)
                .foregroundColor(Theme.darkGray)
        }
    }

    private var roleLabel: String {
        switch user.role {
        case .supervisor: return "Supervisor"
        case .employee: return "Employee"
        case .manager: return "Manager"
        }
    }

    /// Look up the user's assigned locations so the picker has names + addresses.
    /// Falls back to `user.locationId` for older accounts that predate
    /// `assignedLocationIds`, so the existing single-location flow still
    /// works without any data migration.
    private func resolveLocations() async {
        isResolving = true
        resolveError = nil

        let firebase = FirebaseService.shared
        guard let managerUserId = user.managerUserId else {
            // Defensive path — every employee/supervisor User doc should
            // have managerUserId set at signup. If it's missing we can't
            // resolve their locations.
            resolveError = "Your account is missing a manager link. Contact your manager."
            isResolving = false
            return
        }

        do {
            // Pull the employee record from the manager-level mirror —
            // that's the source of truth for `assignedLocationIds`. The
            // per-location subcollection only stores one row per
            // location, so we can't rely on it for the full list.
            let employee = try await firebase.fetchManagerEmployee(
                userId: managerUserId,
                employeeId: user.id
            )

            // Compose the candidate location-id list. We include
            // `user.locationId` defensively in case `assignedLocationIds`
            // hasn't been backfilled on this record yet.
            var candidateIds = Set(employee.assignedLocationIds)
            if let primary = user.locationId, !primary.isEmpty {
                candidateIds.insert(primary)
            }

            guard !candidateIds.isEmpty else {
                resolveError = "You're not assigned to any location yet. Contact your manager."
                isResolving = false
                return
            }

            // Fetch each location individually (in parallel) rather than
            // pulling the whole tenant's location list — avoids leaking
            // location names the user doesn't have access to.
            let locations: [Location] = await withTaskGroup(of: Location?.self) { group in
                for locId in candidateIds {
                    group.addTask {
                        try? await firebase.fetchLocation(userId: managerUserId, locationId: locId)
                    }
                }
                var collected: [Location] = []
                for await loc in group {
                    if let loc { collected.append(loc) }
                }
                return collected.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }

            assignedLocations = locations

            // Single-location users skip the picker entirely.
            if locations.count == 1 {
                activeLocationId = locations[0].id
            } else {
                // Multi-location users land on the picker. Clear any
                // previous in-session selection so a re-resolve (e.g.
                // pull-to-refresh in the future) re-prompts.
                activeLocationId = nil
            }

            isResolving = false
        } catch {
            resolveError = error.localizedDescription
            isResolving = false
        }
    }
}

/// The original `EmployeeHomeView` body, parameterized on a fixed
/// `locationId`. Owns the per-location `EmployeeHomeViewModel`. Recreated
/// from scratch every time the active location changes (via `.id(...)`).
struct EmployeeHomeContent: View {
    let user: User
    @StateObject private var viewModel: EmployeeHomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedTab: EmployeeTab = .clockInOut
    @State private var showingRegisterError = false
    /// Injected by `EmployeeHomeView` when the user is assigned to ≥ 2
    /// locations. Drives the optional "Switch Location" card on the home
    /// screen for everyone (employees + supervisors). When `nil` the
    /// card is hidden — there's nowhere to switch to.
    @Environment(\.requestLocationSwitch) private var requestLocationSwitch

    init(user: User, locationId: String) {
        self.user = user
        _viewModel = StateObject(wrappedValue: EmployeeHomeViewModel(employeeId: user.id, locationId: locationId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Colored Header with App Logo
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                            Text("Oplix")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button("Logout") {
                                authViewModel.signOut()
                            }
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        }
                        
                        // Date and Location Info
                        if let location = viewModel.location {
                            VStack(spacing: 4) {
                                HStack {
                                    Text(formatDate(Date()))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.9))
                                    Text(location.name)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer()
                                }
                            }
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
                    ScrollView {
                        VStack(spacing: 20) {
                            // Employee Name and Location
                            if let employee = viewModel.employee, let location = viewModel.location {
                                VStack(spacing: 8) {
                                    Text(employee.name)
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)

                                    HStack(spacing: 6) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(Theme.cloudBlue)
                                        Text(location.name)
                                            .font(.subheadline)
                                            .foregroundColor(Theme.cloudBlue)
                                        // Inline location-switch chip.
                                        // Only rendered when the shell
                                        // injected a switcher closure
                                        // (i.e. user has ≥ 2 assigned
                                        // locations); otherwise hidden.
                                        if let requestSwitch = requestLocationSwitch {
                                            Button(action: requestSwitch) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Text("Switch")
                                                        .font(.system(size: 12, weight: .semibold))
                                                }
                                                .foregroundColor(Theme.cloudBlue)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Theme.cloudBlue.opacity(0.12))
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule().stroke(Theme.cloudBlue.opacity(0.35), lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Switch location")
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(12)
                                .padding(.horizontal)
                                
                                // Weekly Stats Card
                                WeeklyStatsCard(
                                    hours: viewModel.thisWeekHours,
                                    pay: viewModel.thisWeekPay
                                )
                                .padding(.horizontal)

                                // Performance card — shows the employee's own
                                // task progress today and how the whole
                                // location is doing today + past week. Only
                                // rendered when the location has any
                                // assigned tasks at all.
                                if viewModel.locationTodayScore != nil
                                    || viewModel.locationPastWeekScore != nil
                                    || viewModel.myTodayScore.assigned > 0 {
                                    PerformanceCard(
                                        myToday: viewModel.myTodayScore,
                                        locationToday: viewModel.locationTodayScore,
                                        locationPastWeek: viewModel.locationPastWeekScore
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            
                            // Tab Buttons
                            VStack(spacing: 12) {
                                // Register Data Tab (if has permission)
                                if let employee = viewModel.employee, employee.hasRegisterPermission {
                                    NavigationLink(value: EmployeeTab.registerData) {
                                        EmployeeTabButton(
                                            icon: "cashregister.fill",
                                            title: "Register Data",
                                            color: viewModel.currentShift?.isActive == true ? .blue : .gray
                                        )
                                    }
                                    .padding(.horizontal)
                                    .disabled(viewModel.currentShift?.isActive != true)
                                    .simultaneousGesture(
                                        TapGesture().onEnded {
                                            if viewModel.currentShift?.isActive != true {
                                                showingRegisterError = true
                                            }
                                        }
                                    )
                                }
                                
                                // Lottery Tab (if has permission)
                                if let employee = viewModel.employee, employee.hasLotteryPermission {
                                    NavigationLink(value: EmployeeTab.lottery) {
                                        EmployeeTabButton(
                                            icon: "ticket.fill",
                                            title: "Lottery",
                                            color: .orange
                                        )
                                    }
                                    .padding(.horizontal)
                                }
                                
                                // Clock In/Out Tab
                                NavigationLink(value: EmployeeTab.clockInOut) {
                                    EmployeeTabButton(
                                        icon: "clock.fill",
                                        title: "Clock In/Out",
                                        color: .green
                                    )
                                }
                                .padding(.horizontal)
                                
                                // Tasks Tab
                                NavigationLink(value: EmployeeTab.tasks) {
                                    EmployeeTabButton(
                                        icon: "checklist",
                                        title: "Tasks",
                                        color: .purple
                                    )
                                }
                                .padding(.horizontal)
                                
                                // Schedule Tab
                                NavigationLink(value: EmployeeTab.schedule) {
                                    EmployeeTabButton(
                                        icon: "calendar",
                                        title: "Schedule",
                                        color: .indigo
                                    )
                                }
                                .padding(.horizontal)
                                
                                // Supervise Tab (only for supervisors)
                                // Show tab for any supervisor since invoices are always available
                                if let employee = viewModel.employee,
                                   let user = authViewModel.currentUser,
                                   user.role == .supervisor {
                                    NavigationLink(value: EmployeeTab.supervise) {
                                        EmployeeTabButton(
                                            icon: "person.badge.key.fill",
                                            title: "Supervisor",
                                            color: .purple
                                        )
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Set navigation bar appearance to ensure proper text colors
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = UIColor.clear
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
                appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
            .task(id: viewModel.employeeId) {
                // Only load if not already loaded (allow loading even if isLoading is true initially)
                guard viewModel.employee == nil || viewModel.location == nil else {
                    print("⚠️ Skipping loadData - data already loaded")
                    return
                }
                await viewModel.loadData()
                viewModel.startObserving()
            }
            .alert("Error", isPresented: $showingRegisterError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You must be clocked in to enter register data. Please clock in first.")
            }
            .navigationDestination(for: EmployeeTab.self) { tab in
                switch tab {
                case .registerData:
                    EmployeeRegisterDataView(viewModel: viewModel)
                case .lottery:
                    EmployeeLotteryView(viewModel: viewModel)
                case .clockInOut:
                    EmployeeClockInOutView(viewModel: viewModel)
                case .tasks:
                    EmployeeTasksView(viewModel: viewModel)
                case .schedule:
                    EmployeeScheduleView(viewModel: viewModel)
                case .supervise:
                    SupervisorControlsView(viewModel: viewModel)
                }
            }
        }
    }
    
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy" // e.g., "Monday, January 15, 2025"
        return formatter.string(from: date)
    }
}

// MARK: - Employee Tab Enum
enum EmployeeTab: String, Identifiable, Hashable {
    case registerData, lottery, clockInOut, tasks, schedule, supervise
    
    var id: String { rawValue }
}

// MARK: - Weekly Stats Card
struct WeeklyStatsCard: View {
    let hours: Double
    let pay: Double
    
    var body: some View {
        HStack(spacing: 30) {
            VStack(spacing: 4) {
                Text("This Week")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
                Text("\(String(format: "%.1f", hours)) hrs")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(spacing: 4) {
                Text("This Week")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
                Text(formatCurrency(pay))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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

// MARK: - Performance Card
/// Compact card shown on the supervisor / team-member home screen. Top half
/// is the signed-in user's *personal* task progress for the current cycle
/// (the same number the manager sees on their employee row). Bottom half is
/// the *location's* today + past-week scores, so the employee can see how
/// their team is doing as a whole.
///
/// Score bars match the manager dashboard's white-on-gradient look so the
/// numbers feel consistent across roles.
struct PerformanceCard: View {
    let myToday: (completed: Int, assigned: Int)
    let locationToday: LocationScoreSegment?
    let locationPastWeek: LocationScoreSegment?

    private var myPercentage: Double {
        guard myToday.assigned > 0 else { return 0 }
        return min(max(Double(myToday.completed) / Double(myToday.assigned), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Personal score
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Your Tasks Today")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    if myToday.assigned > 0 {
                        Text("\(myToday.completed)/\(myToday.assigned)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("None today")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }

                if myToday.assigned > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(4, geo.size.width * myPercentage))
                        }
                    }
                    .frame(height: 8)
                }
            }

            // Location scores (only if at least one is available)
            if locationToday != nil || locationPastWeek != nil {
                Divider()
                    .background(Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Location")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }

                    if let today = locationToday {
                        scoreTrack(label: "TODAY", segment: today)
                    }
                    if let week = locationPastWeek {
                        scoreTrack(label: "PAST WEEK", segment: week)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
                .frame(width: 92, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Employee Tab Button
struct EmployeeTabButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(Theme.darkGray)
                .font(.caption)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Custom TextField with Visible Placeholder
struct RegisterTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    var isDisabled: Bool = false
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.textColor = .black
        textField.backgroundColor = .white
        textField.layer.borderColor = UIColor.gray.withAlphaComponent(0.5).cgColor
        textField.layer.borderWidth = 1
        textField.layer.cornerRadius = 8
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 0))
        textField.rightViewMode = .always
        textField.isEnabled = !isDisabled
        
        // Set placeholder color to be more visible
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.gray.withAlphaComponent(0.7)]
        )
        
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        uiView.isEnabled = !isDisabled
        // Update placeholder color if needed
        if uiView.placeholder == placeholder {
            uiView.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: UIColor.gray.withAlphaComponent(0.7)]
            )
        }
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        // Return a size that matches typical TextField height
        return CGSize(width: proposal.width ?? UIView.layoutFittingExpandedSize.width, height: 44)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: RegisterTextField
        
        init(_ parent: RegisterTextField) {
            self.parent = parent
        }
        
        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }
}

// MARK: - Shift Register Entry Card
struct ShiftRegisterEntryCard: View {
    let shift: Shift
    @Binding var registers: [RegisterData]
    @Binding var expenseDescriptions: [String]
    @Binding var expenseAmounts: [String]
    let savedRegisterIds: Set<String> // Track which registers have been saved
    var isReadOnly: Bool = false // If true, all fields are read-only
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Register Sections
            ForEach(Array(registers.enumerated()), id: \.element.id) { index, register in
                let isSaved = savedRegisterIds.contains(register.id) || isReadOnly
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Register \(index + 1)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.cloudBlue)
                        
                        if isSaved {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Saved")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                        
                        // Delete button (only show if more than one register and not saved/read-only)
                        if registers.count > 1 && !isSaved && !isReadOnly {
                            Button(action: {
                                registers.remove(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    // Cash Sale
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cash Sale")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        RegisterTextField(
                            text: Binding(
                                get: { register.cashSale },
                                set: { if !isSaved { registers[index].cashSale = $0 } }
                            ),
                            placeholder: "Enter amount",
                            keyboardType: .decimalPad,
                            isDisabled: isSaved
                        )
                        .frame(height: 44)
                        .opacity(isSaved ? 0.6 : 1.0)
                    }
                    
                    // Cash In Hand
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cash In Hand")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        RegisterTextField(
                            text: Binding(
                                get: { register.cashInHand },
                                set: { if !isSaved { registers[index].cashInHand = $0 } }
                            ),
                            placeholder: "Enter amount",
                            keyboardType: .decimalPad,
                            isDisabled: isSaved
                        )
                        .frame(height: 44)
                        .opacity(isSaved ? 0.6 : 1.0)
                    }
                    
                    // Cash Expense Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cash Expense")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.cloudBlue)
                            Spacer()
                            if !isSaved && !isReadOnly {
                                Button(action: {
                                    registers[index].cashExpenseDescriptions.append("")
                                    registers[index].cashExpenseAmounts.append("")
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        ForEach(Array(register.cashExpenseDescriptions.indices), id: \.self) { expenseIndex in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    // Description field (left)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Description")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        RegisterTextField(
                                            text: Binding(
                                                get: { expenseIndex < register.cashExpenseDescriptions.count ? register.cashExpenseDescriptions[expenseIndex] : "" },
                                                set: { newValue in
                                                    if !isSaved && expenseIndex < registers[index].cashExpenseDescriptions.count {
                                                        registers[index].cashExpenseDescriptions[expenseIndex] = newValue
                                                    }
                                                }
                                            ),
                                            placeholder: "Enter description",
                                            keyboardType: .default,
                                            isDisabled: isSaved
                                        )
                                        .frame(height: 44)
                                        .opacity(isSaved ? 0.6 : 1.0)
                                    }
                                    
                                    // Amount field (right)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Amount")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        RegisterTextField(
                                            text: Binding(
                                                get: { expenseIndex < register.cashExpenseAmounts.count ? register.cashExpenseAmounts[expenseIndex] : "" },
                                                set: { newValue in
                                                    if !isSaved && expenseIndex < registers[index].cashExpenseAmounts.count {
                                                        registers[index].cashExpenseAmounts[expenseIndex] = newValue
                                                    }
                                                }
                                            ),
                                            placeholder: "Enter amount",
                                            keyboardType: .decimalPad,
                                            isDisabled: isSaved
                                        )
                                        .frame(width: 100, height: 44)
                                        .opacity(isSaved ? 0.6 : 1.0)
                                    }
                                    
                                    // Delete button (only show if more than one row and not saved/read-only)
                                    if register.cashExpenseDescriptions.count > 1 && !isSaved && !isReadOnly {
                                        VStack {
                                            Spacer()
                                            Button(action: {
                                                if expenseIndex < registers[index].cashExpenseDescriptions.count {
                                                    registers[index].cashExpenseDescriptions.remove(at: expenseIndex)
                                                }
                                                if expenseIndex < registers[index].cashExpenseAmounts.count {
                                                    registers[index].cashExpenseAmounts.remove(at: expenseIndex)
                                                }
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                            .padding(.top, 20)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Total Cash Expenses
                        let totalCashExpenses = register.cashExpenseAmounts.compactMap { Double($0) }.reduce(0, +)
                        if totalCashExpenses > 0 {
                            Divider()
                            HStack {
                                Text("Total Cash Expenses:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                                Text(formatCurrency(totalCashExpenses))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    // Over/Short - Auto-calculated (read-only)
                    // Note: Cash expense is added to cash in hand for calculation
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Over/Short")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        HStack {
                            Text(calculatedOverShort(for: register))
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(calculatedOverShortValue(for: register) >= 0 ? .green : .red)
                            Spacer()
                            Text("(Auto-calculated)")
                                .font(.caption2)
                                .foregroundColor(Theme.darkGray)
                                .italic()
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Credit Card
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Credit Card")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        RegisterTextField(
                            text: Binding(
                                get: { register.creditCard },
                                set: { if !isSaved { registers[index].creditCard = $0 } }
                            ),
                            placeholder: "Enter amount",
                            keyboardType: .decimalPad,
                            isDisabled: isSaved
                        )
                        .frame(height: 44)
                        .opacity(isSaved ? 0.6 : 1.0)
                    }
                    
                    // Fuel Sale Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fuel Sale")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.cloudBlue)
                        
                        // Gallons Sold
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Gallons Sold")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                            RegisterTextField(
                                text: Binding(
                                    get: { register.fuelSaleGallons },
                                    set: { if !isSaved { registers[index].fuelSaleGallons = $0 } }
                                ),
                                placeholder: "Enter gallons",
                                keyboardType: .decimalPad,
                                isDisabled: isSaved
                            )
                            .frame(height: 44)
                            .opacity(isSaved ? 0.6 : 1.0)
                        }
                        
                        // Dollars
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dollars")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                            RegisterTextField(
                                text: Binding(
                                    get: { register.fuelSaleDollars },
                                    set: { if !isSaved { registers[index].fuelSaleDollars = $0 } }
                                ),
                                placeholder: "Enter amount",
                                keyboardType: .decimalPad,
                                isDisabled: isSaved
                            )
                            .frame(height: 44)
                            .opacity(isSaved ? 0.6 : 1.0)
                        }
                    }
                }
                .padding(.bottom, index < registers.count - 1 ? 20 : 0)
            }
            
            // Expenses Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Expenses (Non Cash, Check)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.cloudBlue)
                    Spacer()
                    if !isReadOnly {
                        Button(action: {
                            expenseDescriptions.append("")
                            expenseAmounts.append("")
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                ForEach(Array(expenseDescriptions.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            // Description field (left)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                RegisterTextField(
                                    text: Binding(
                                        get: { index < expenseDescriptions.count ? expenseDescriptions[index] : "" },
                                        set: { newValue in
                                            if !isReadOnly && index < expenseDescriptions.count {
                                                expenseDescriptions[index] = newValue
                                            }
                                        }
                                    ),
                                    placeholder: "Enter description",
                                    keyboardType: .default,
                                    isDisabled: isReadOnly
                                )
                                .frame(height: 44)
                                .opacity(isReadOnly ? 0.6 : 1.0)
                            }
                            
                            // Amount field (right)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Amount")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                RegisterTextField(
                                    text: Binding(
                                        get: { index < expenseAmounts.count ? expenseAmounts[index] : "" },
                                        set: { newValue in
                                            if !isReadOnly && index < expenseAmounts.count {
                                                expenseAmounts[index] = newValue
                                            }
                                        }
                                    ),
                                    placeholder: "Enter amount",
                                    keyboardType: .decimalPad,
                                    isDisabled: isReadOnly
                                )
                                .frame(width: 100, height: 44)
                                .opacity(isReadOnly ? 0.6 : 1.0)
                            }
                            
                            // Delete button (only show if more than one row and not read-only)
                            if expenseDescriptions.count > 1 && !isReadOnly {
                                VStack {
                                    Spacer()
                                    Button(action: {
                                        if index < expenseDescriptions.count {
                                            expenseDescriptions.remove(at: index)
                                        }
                                        if index < expenseAmounts.count {
                                            expenseAmounts.remove(at: index)
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .padding(.top, 20)
                                }
                            }
                        }
                    }
                }
                
                // Total Expenses
                let totalExpenses = expenseAmounts.compactMap { Double($0) }.reduce(0, +)
                if totalExpenses > 0 {
                    Divider()
                    HStack {
                        Text("Total Expenses:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        Spacer()
                        Text(formatCurrency(totalExpenses))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Add Next Register Button (only show if not read-only)
            if !isReadOnly {
                Button(action: {
                    registers.append(RegisterData())
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Next Register")
                    }
                    .frame(maxWidth: .infinity)
                    .cloudButton(backgroundColor: .blue)
                }
                
                // Close Register Button (only show if not read-only)
                Button(action: onSave) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Close Register")
                    }
                    .frame(maxWidth: .infinity)
                    .cloudButton(backgroundColor: .green)
                }
            }
        }
        .padding()
        .cloudCard()
    }
    
    private func calculatedOverShort(for register: RegisterData) -> String {
        let sale = Double(register.cashSale) ?? 0.0
        let inHand = Double(register.cashInHand) ?? 0.0
        // Sum all cash expenses
        let totalCashExpense = register.cashExpenseAmounts.compactMap { Double($0) }.reduce(0, +)
        // Cash expense is added to cash in hand for calculation
        let adjustedCashInHand = inHand + totalCashExpense
        let calculated = adjustedCashInHand - sale
        return formatCurrency(calculated)
    }
    
    private func calculatedOverShortValue(for register: RegisterData) -> Double {
        let sale = Double(register.cashSale) ?? 0.0
        let inHand = Double(register.cashInHand) ?? 0.0
        // Sum all cash expenses
        let totalCashExpense = register.cashExpenseAmounts.compactMap { Double($0) }.reduce(0, +)
        // Cash expense is added to cash in hand for calculation
        let adjustedCashInHand = inHand + totalCashExpense
        return adjustedCashInHand - sale
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

struct ClockInOutCard: View {
    let employee: Employee
    let location: Location?
    let currentShift: Shift?
    let onClockIn: () -> Void
    let onClockOut: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Working Hours Info (if set)
            if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                VStack(spacing: 4) {
                    Text("Working Hours")
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                    HStack(spacing: 8) {
                        Text(startTime)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        Text("-")
                            .font(.subheadline)
                            .foregroundColor(Theme.darkGray)
                        Text(endTime)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                }
                .padding(.bottom, 8)
            }
            
            if let shift = currentShift {
                if shift.isActive {
                    // Shift is active (clocked in) - Show Clock Out
                    VStack(spacing: 8) {
                        Text("Clocked In")
                            .font(.headline)
                            .foregroundColor(.black)
                        if let clockInTime = shift.clockInTime {
                            Text(clockInTime, style: .time)
                                .font(.title2)
                                .foregroundColor(.black)
                        }
                        
                        // Show duration if available
                        if let hoursWorked = shift.hoursWorked {
                            Text("Duration: \(String(format: "%.1f", hoursWorked)) hours")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        }
                        
                        Button(action: onClockOut) {
                            Text("Clock Out")
                                .frame(maxWidth: .infinity)
                                .cloudButton(backgroundColor: .red)
                        }
                    }
                } else if shift.isCompleted {
                    // Shift is completed - Show read-only info
                    VStack(spacing: 8) {
                        Text("Shift Completed")
                            .font(.headline)
                            .foregroundColor(.black)
                        if let clockInTime = shift.clockInTime, let clockOutTime = shift.clockOutTime {
                            VStack(spacing: 4) {
                                HStack {
                                    Text("In:")
                                        .font(.caption)
                                        .foregroundColor(Theme.darkGray)
                                    Text(clockInTime, style: .time)
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                }
                                HStack {
                                    Text("Out:")
                                        .font(.caption)
                                        .foregroundColor(Theme.darkGray)
                                    Text(clockOutTime, style: .time)
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        if let hoursWorked = shift.hoursWorked {
                            Text("Total: \(String(format: "%.1f", hoursWorked)) hours")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        }
                    }
                } else {
                    // Shift is assigned but not started - Show Clock In
                    Button(action: onClockIn) {
                        Text("Clock In")
                            .frame(maxWidth: .infinity)
                            .cloudButton()
                    }
                }
            } else {
                // No shift - Show Clock In
                Button(action: onClockIn) {
                    Text("Clock In")
                        .frame(maxWidth: .infinity)
                        .cloudButton()
                }
            }
        }
        .padding()
        .cloudCard()
        .padding(.horizontal)
    }
}

struct TaskCard: View {
    let task: WorkTask
    let employee: Employee
    let onComplete: () -> Void
    
    @State private var previewImage: UIImage?
    @State private var showingImageViewer = false
    
    private var isCompleted: Bool {
        task.isCompletedBy(employeeId: employee.id)
    }
    
    private var completion: TaskCompletion? {
        task.getCompletion(for: employee.id)
    }

    /// True when the manager reviewed and disapproved this employee's photo
    /// for the current cycle. The task auto-flips back to "not done" via
    /// `isCompletedBy`, but we surface a banner so the employee knows *why*
    /// the previous "done" status disappeared.
    private var isDisapproved: Bool {
        completion?.isDisapproved == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Disapproval banner — shown when the manager rejected the most
            // recent photo. The task is no longer marked complete, so the
            // employee can re-tap the circle to redo it.
            if isDisapproved {
                disapprovalBanner
            }

            HStack {
                Button(action: {
                    if !isCompleted {
                        onComplete()
                    }
                }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isCompleted ? .green : (isDisapproved ? .red : Theme.darkGray))
                        .font(.title2)
                }
                .disabled(isCompleted)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.description)
                            .font(.body)
                            .strikethrough(isCompleted)
                            .foregroundColor(isCompleted ? Theme.darkGray : .black)

                        if isCompleted {
                            Text("DONE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .cornerRadius(8)
                        } else if isDisapproved {
                            Text("REDO")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                    }

                    if let completion = completion {
                        Text("Completed: \(completion.timestamp, style: .date) at \(completion.timestamp, style: .time)")
                            .font(.caption2)
                            .foregroundColor(Theme.darkGray)
                    }
                }
                
                Spacer()
            }
            
            // Preview image section
            if isCompleted, let completion = completion {
                HStack(spacing: 12) {
                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(8)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "photo.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(completion.imageURLs.count > 1 ? "\(completion.imageURLs.count) photos submitted" : "Photo submitted")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        }
                        
                        Text("Tap to view full image")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                .onTapGesture {
                    showingImageViewer = true
                }
                .task {
                    // Load first image from imageURLs array, or fallback to imageURL for backward compatibility
                    let imageURLString = completion.imageURLs.first ?? completion.imageURL
                    await loadPreviewImage(from: imageURLString)
                }
            }
        }
        .padding()
        .cloudCard()
        .sheet(isPresented: $showingImageViewer) {
            if let completion = completion {
                TaskImagesView(
                    imageURLs: completion.imageURLs.isEmpty ? [completion.imageURL] : completion.imageURLs,
                    timestamp: completion.timestamp
                )
            }
        }
    }
    
    private func loadPreviewImage(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    previewImage = image
                }
            }
        } catch {
            print("Failed to load preview image: \(error)")
        }
    }

    /// Red banner shown above the row when the manager disapproved the
    /// employee's most recent photo. Surfaces the optional reason and tells
    /// the employee they need to redo the task.
    private var disapprovalBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Photo disapproved — please redo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)

                if let note = completion?.disapprovalNote, !note.isEmpty {
                    Text("Reason: \(note)")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

#Preview {
    EmployeeHomeView(user: User(
        id: "test",
        username: "testuser",
        role: .employee,
        locationId: "loc1",
        managerUserId: "manager1",
        createdAt: Date()
    ))
    .environmentObject(AuthViewModel())
}
