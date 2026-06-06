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
    // When true, a top-right "Done" button is added to the toolbar.
    // Callers that present this view modally (e.g. fullScreenCover from
    // the Home Action Center) MUST set this to true — otherwise the
    // user has no system back button and gets trapped on the screen.
    let showsCloseButton: Bool
    @StateObject private var viewModel: LocationDetailViewModel
    // Per-location "Needs Attention" feed. Replaces the old stats strip
    // (employees / hours / payout) on the location header — the stats
    // are still available inside Payroll / Employees screens, but the
    // top of the location screen is now action-oriented instead.
    @StateObject private var alertsViewModel: LocationAlertsViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showingAddEmployee = false
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var showingSalesExpenses = false
    @State private var showingEditLocation = false
    @State private var recurringPayablesCount = 0
    @State private var recurringReceivablesCount = 0
    @State private var openRemindersCount = 0
    // Target pushed programmatically when the user taps a Needs
    // Attention row. Distinct from the existing `NavigationLink(value:)`
    // flow that drives the icon grid. We use an enum (rather than two
    // separate state vars) because SwiftUI only honours one
    // `.navigationDestination(...)` push at a time on a given view —
    // having two of them with overlapping bindings makes one silently
    // lose.
    @State private var alertNavTarget: AlertNavTarget?
    @Environment(\.dismiss) var dismiss

    /// Where to push when an alert row is tapped. Either deep-links into
    /// a specific employee's profile (for alerts that name an individual,
    /// e.g. "Jon forgot to clock out") or falls back to the relevant
    /// section screen for the location.
    enum AlertNavTarget: Hashable {
        case section(LocationSection)
        case employee(Employee)
    }
    
    init(userId: String, locationId: String, showsCloseButton: Bool = false) {
        self.userId = userId
        self.locationId = locationId
        self.showsCloseButton = showsCloseButton
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: userId, locationId: locationId))
        _alertsViewModel = StateObject(wrappedValue: LocationAlertsViewModel(userId: userId, locationId: locationId))
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
                    // Header — tap the name or the pencil to edit the
                    // location's name + address. Address is intentionally
                    // not part of the tap target so a long address
                    // doesn't accidentally launch the editor.
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(location.name)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Text(location.address)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showingEditLocation = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.cloudBlue)
                                .frame(width: 36, height: 36)
                                .background(Theme.cloudBlue.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Edit location")
                    }
                    .padding()
                    .background(Theme.cloudWhite)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingEditLocation = true
                    }
                    
                    // Per-location Needs Attention feed + iOS Home-Screen
                    // style section grid — share the same ScrollView so
                    // they scroll together on smaller phones.
                    ScrollView {
                        VStack(spacing: 16) {
                            // Only render the Attention card when there's
                            // something to show OR we're still loading the
                            // first batch; otherwise the empty "all caught
                            // up" state would push the icon grid down for
                            // no reason on a clean location.
                            let locationAlerts = alertsViewModel.alerts
                                .filteringAcknowledged(authViewModel.acknowledgedAlertIdSet)
                            if alertsViewModel.isLoading || !locationAlerts.isEmpty {
                                ActionCenterCard(
                                    alerts: locationAlerts,
                                    isLoading: alertsViewModel.isLoading,
                                    onTapAlert: handleAlertTap,
                                    onAcknowledge: { alert in
                                        Task { await authViewModel.acknowledgeAlert(alert.id) }
                                    }
                                )
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }

                            LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 24) {
                            NavigationLink(value: LocationSection.employees) {
                                SectionIconCard(
                                    icon: "person.2.fill",
                                    title: "Employees",
                                    color: .blue,
                                    count: viewModel.employees.count,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(value: LocationSection.supervisors) {
                                SectionIconCard(
                                    icon: "person.badge.key.fill",
                                    title: "Supervisors",
                                    color: .purple,
                                    count: viewModel.supervisors.count,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(value: LocationSection.tasks) {
                                SectionIconCard(
                                    icon: "checklist",
                                    title: "Tasks",
                                    color: .green,
                                    count: viewModel.tasks.count,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(value: LocationSection.shifts) {
                                SectionIconCard(
                                    icon: "clock.fill",
                                    title: "Shift Manager",
                                    color: .purple,
                                    count: viewModel.shifts.count,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(value: LocationSection.lottery) {
                                SectionIconCard(
                                    icon: "ticket.fill",
                                    title: "Lottery",
                                    color: .orange,
                                    count: viewModel.lotteryForms.count,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(value: LocationSection.documents) {
                                SectionIconCard(
                                    icon: "doc.fill",
                                    title: "Documents",
                                    color: .indigo,
                                    count: 0,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(value: LocationSection.reminders) {
                                SectionIconCard(
                                    icon: "bell.fill",
                                    title: "Reminders",
                                    color: .pink,
                                    count: 0,
                                    badgeCount: openRemindersCount > 0 ? openRemindersCount : nil,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(value: LocationSection.payroll) {
                                SectionIconCard(
                                    icon: "dollarsign.circle.fill",
                                    title: "Payroll",
                                    color: .green,
                                    count: 0,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)

                            if authViewModel.currentUser?.role == .manager {
                                NavigationLink {
                                    ReportsHubView(
                                        userId: userId,
                                        organizationName: authViewModel.currentUser?.organizationName,
                                        preselectedLocationId: locationId
                                    )
                                } label: {
                                    SectionIconCard(
                                        icon: "doc.text.magnifyingglass",
                                        title: "Reports",
                                        color: .cyan,
                                        count: 0,
                                        showCount: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button(action: {
                                showingSalesExpenses = true
                            }) {
                                SectionIconCard(
                                    icon: "chart.bar.fill",
                                    title: "Sales",
                                    color: .teal,
                                    count: 0,
                                    showCount: false
                                )
                            }
                            .buttonStyle(.plain)
                            
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
                            .buttonStyle(.plain)
                            
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
                            .buttonStyle(.plain)
                            
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        }
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
            destinationView(for: section)
        }
        // Programmatic push triggered by tapping a row in the Needs
        // Attention card. We use `isPresented:` (not `item:`) because
        // pairing `item:` with the `for:`-style destination above
        // produces a known SwiftUI 17/18 conflict where one of them
        // silently loses.
        .navigationDestination(
            isPresented: Binding(
                get: { alertNavTarget != nil },
                set: { isPresented in
                    if !isPresented { alertNavTarget = nil }
                }
            )
        ) {
            switch alertNavTarget {
            case .section(let section):
                destinationView(for: section)
            case .employee(let employee):
                // Deep-link into the named employee's profile. Reuses
                // the same destination EmployeesScreen shows when you
                // tap a row there.
                EmployeeDetailView(employee: employee, viewModel: viewModel)
            case .none:
                EmptyView()
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
        // Floating action controls in the bottom corners. The trash
        // (delete) sits bottom-left and the modal-close "Done" button
        // sits bottom-right — both with a soft white pill background
        // so they read as proper FABs over the scroll content. Done
        // is hidden when the view is pushed onto a NavigationStack
        // (the system back button already gives an exit) so we don't
        // show two of them.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(color: Color.red.opacity(0.35), radius: 6, x: 0, y: 3)
                }
                .accessibilityLabel("Delete location")
                
                Spacer()
                
                if showsCloseButton {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .frame(height: 52)
                            .background(Theme.cloudBlue)
                            .clipShape(Capsule())
                            .shadow(color: Theme.cloudBlue.opacity(0.35), radius: 6, x: 0, y: 3)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
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
            
            // Load per-location Needs Attention alerts (replaces the
            // old employees/hours/payout stats strip).
            await alertsViewModel.loadAlerts()

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
        .onChange(of: showingAddEmployee) { _, isShowing in
            guard !isShowing else { return }
            Task {
                await viewModel.reloadData()
                await alertsViewModel.loadAlerts()
            }
        }
        .sheet(isPresented: $showingSalesExpenses) {
            print("🟡 SHEET - SalesExpensesScreen PRESENTED")
            return SalesExpensesScreen(viewModel: viewModel)
        }
        .sheet(isPresented: $showingEditLocation) {
            EditLocationView(viewModel: viewModel)
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
    
    // Maps an alert tap to its best destination. We try to deep-link
    // into the *specific* employee a row is about first (e.g. tapping
    // "Jon forgot to clock out" should land on Jon's profile, not on
    // a generic Shifts list where Jim happens to sit at the top).
    // Falls back to the relevant section if no employee can be resolved.
    //
    // Kept as a switch (not a dictionary) so the compiler catches us if
    // we add a new ManagerAlertCategory and forget to wire it through.
    private func handleAlertTap(_ alert: ActionAlert) {
        if let employee = employeeFromAlert(alert) {
            alertNavTarget = .employee(employee)
            return
        }

        let section: LocationSection?
        switch alert.category {
        case .forgotClockOut, .missingRegister, .cashVariance:
            section = .shifts
        case .lotteryNotClosed, .lotteryVariance:
            section = .lottery
        case .disapprovedTasks:
            section = .tasks
        case .overduePayables:
            section = .payables
        case .expiringDocs:
            section = .documents
        case .scheduleGaps:
            // Schedule-gap alerts always name an individual, so if we
            // got here it means the employee wasn't found in the local
            // cache (e.g. just deleted). Fall back to the Employees list.
            section = .employees
        }
        if let section = section {
            alertNavTarget = .section(section)
        }
    }

    /// For alerts that explicitly name an employee (forgot clock-out,
    /// missing register, schedule gap), resolve the employee from
    /// `alert.id` so we can push their profile directly. Returns nil
    /// for category-level alerts (overdue payables, expiring docs, etc.)
    /// where no single person owns the row.
    ///
    /// Searches both `employees` and `supervisors` because the location
    /// view-model splits the raw fetch into two pools by role — without
    /// this we'd miss any supervisor-targeted alert and silently fall
    /// back to the Employees list (which doesn't even contain them).
    private func employeeFromAlert(_ alert: ActionAlert) -> Employee? {
        let id = alert.id
        let staff = viewModel.employees + viewModel.supervisors

        // "schedgap_<empId>" — alert.id already carries the employee id.
        if let empId = id.stripPrefix("schedgap_") {
            return staff.first { $0.id == empId }
        }

        // "clockout_<shiftId>" / "noregister_<shiftId>" — resolve the
        // shift first, then the shift's employee.
        let shiftIdPrefixes = ["clockout_", "noregister_"]
        for prefix in shiftIdPrefixes {
            if let shiftId = id.stripPrefix(prefix),
               let shift = viewModel.shifts.first(where: { $0.id == shiftId }) {
                return staff.first { $0.id == shift.employeeId }
            }
        }

        return nil
    }

    // Shared destination builder used by both the icon-grid
    // `NavigationLink(value:)` flow and the alert-tap programmatic push.
    @ViewBuilder
    private func destinationView(for section: LocationSection) -> some View {
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
        case .reminders:
            LocationRemindersView(userId: userId, locationId: locationId) {
                Task { await loadRecurringCounts() }
            }
        }
    }

    private func loadRecurringCounts() async {
        do {
            let payables = try await FirebaseService.shared.fetchPayables(userId: userId, locationId: locationId)
            // Only count recurring items that are NOT paid
            recurringPayablesCount = payables.filter { $0.frequency != .none && !$0.isPaid }.count
            
            let receivables = try await FirebaseService.shared.fetchReceivables(userId: userId, locationId: locationId)
            // Only count recurring items that are NOT received
            recurringReceivablesCount = receivables.filter { $0.frequency != .none && !$0.isReceived }.count

            let reminders = try await FirebaseService.shared.fetchLocationReminders(userId: userId, locationId: locationId)
            openRemindersCount = reminders.filter { !$0.isCompleted }.count
        } catch {
            print("Error loading recurring counts: \(error.localizedDescription)")
        }
    }
}

// MARK: - String helpers

private extension String {
    /// Returns the substring after `prefix` when this string starts with
    /// it, otherwise nil. Used to pull entity ids out of `ActionAlert.id`
    /// (e.g. "schedgap_<empId>" → "<empId>") when routing alert taps.
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

#Preview {
    NavigationStack {
        LocationDetailView(userId: "test-user", locationId: "test-location")
            .environmentObject(AuthViewModel())
    }
}
