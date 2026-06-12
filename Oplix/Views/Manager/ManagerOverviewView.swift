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
    @StateObject private var alertsViewModel: HomeAlertsViewModel
    // User's per-device Home layout prefs (toggle + reorder sections).
    // Same store the Settings → Home Layout screen writes to, so changes
    // there are reflected immediately on next render of this view.
    @StateObject private var layoutStore: HomeLayoutStore
    @StateObject private var orgTodosViewModel: OrgTodosViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedLocation: Location?
    // Separate state from selectedLocation so the "Stats By Month" cards
    // keep opening LocationMonthlyStatsView while alert taps open the full
    // location detail view (where the manager actually fixes the issue).
    @State private var selectedLocationForAlert: Location?
    @State private var showingAllShifts = false
    @State private var showingPayroll = false
    @State private var showingInvoices = false
    @State private var showingAllStatus = false
    @State private var showingAnnouncement = false
    @State private var dueThisWeekKind: DueThisWeekKind? = nil
    
    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: ManagerOverviewViewModel(userId: userId))
        _alertsViewModel = StateObject(wrappedValue: HomeAlertsViewModel(userId: userId))
        // Shared per-user instance so toggles in Settings → Home Layout
        // re-render the manager Home immediately (same ObservableObject).
        _layoutStore = StateObject(wrappedValue: HomeLayoutStore.shared(userId: userId))
        _orgTodosViewModel = StateObject(wrappedValue: OrgTodosViewModel(userId: userId))
    }
    
    // Time-of-day greeting. Uses the user's local clock so 11pm shows
    // "Good evening" even though the data was loaded at UTC noon.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hi"
        }
    }
    
    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMM d"
        return f.string(from: Date())
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea(edges: .top) // Only ignore top safe area
                
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
                                if viewModel.isRefreshingHomeDetails {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.bottom, 4)
                                }
                                // Greeting + date + meta-chips. Always shown —
                                // it's the screen's identity (who you're
                                // logged in as, today's date) and isn't
                                // toggleable in the customization sheet.
                                greetingBlock
                                
                                // Render every section the user has visible,
                                // in the order they chose. Customization
                                // happens in Settings → Preferences →
                                // Home Layout (HomeCustomizationView).
                                ForEach(layoutStore.prefs.visibleSectionsInOrder) { sectionId in
                                    section(for: sectionId)
                                }
                                
                                if let errorMessage = viewModel.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding()
                                }
                            }
                            .padding(.top)
                            .padding(.bottom, 24) // Breathing room above the fixed custom tab bar
                        }
                        .scrollContentBackground(.hidden)
                    }
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
                // Existing overview data + alerts in parallel so neither blocks the other.
                async let a: () = viewModel.loadOverview()
                async let b: () = alertsViewModel.loadAlerts()
                _ = await (a, b)
            }
            .refreshable {
                async let a: () = viewModel.loadOverview()
                async let b: () = alertsViewModel.loadAlerts()
                _ = await (a, b)
            }
            .fullScreenCover(item: $selectedLocation) { location in
                LocationMonthlyStatsView(
                    userId: userId,
                    locationId: location.id,
                    locationName: location.name
                )
            }
            // Alert taps open the full location detail (where the actual
            // fix lives), separate from the Stats By Month cards above.
            .fullScreenCover(item: $selectedLocationForAlert) { location in
                NavigationStack {
                    LocationDetailView(
                        userId: userId,
                        locationId: location.id,
                        showsCloseButton: true
                    )
                    .environmentObject(authViewModel)
                }
            }
            .fullScreenCover(isPresented: $showingAllShifts) {
                AllShiftsView(userId: userId)
            }
            .fullScreenCover(isPresented: $showingPayroll) {
                PayrollView(userId: userId)
            }
            .fullScreenCover(isPresented: $showingAllStatus) {
                AllLocationsStatusView(userId: userId)
                    .environmentObject(authViewModel)
            }
            .fullScreenCover(isPresented: $showingAnnouncement) {
                SendAnnouncementView(userId: userId, locations: viewModel.locations)
            }
            // Drill-down for the This Week card. Tapping a row inside
            // the sheet dismisses it and (after a beat to avoid the
            // SwiftUI dual-presentation glitch) opens that location.
            .sheet(item: $dueThisWeekKind) { kind in
                DueThisWeekSheet(
                    kind: kind,
                    pulse: alertsViewModel.weeklyPulse,
                    onSelectLocation: { locId in
                        if let loc = viewModel.locations.first(where: { $0.id == locId }) {
                            selectedLocationForAlert = loc
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingInvoices) {
                InvoicesListView(userId: userId)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Greeting + chips
    
    @ViewBuilder
    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(greeting)\(viewModel.organizationName.map { ", \($0)" } ?? "")")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
            Text(todayString)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Lightweight chip row replacing the old 3 big stat cards
            // (locations / employees / tasks). These were just counts —
            // a chip row carries the same info in ~1/5 the vertical space.
            chipRow
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)
    }
    
    private var chipRow: some View {
        HStack(spacing: 8) {
            metaChip(icon: "building.2.fill", count: viewModel.totalLocations, word: "location")
            metaChip(icon: "person.2.fill", count: viewModel.totalEmployees, word: "employee")
            metaChip(icon: "checklist", count: viewModel.totalTasks, word: "task")
            Spacer()
        }
    }
    
    private func metaChip(icon: String, count: Int, word: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
            Text(count == 1 ? word : "\(word)s")
                .font(.system(size: 12))
        }
        .foregroundColor(Theme.cloudBlue)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.9))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Theme.cloudBlue.opacity(0.25), lineWidth: 1)
        )
    }
    
    // MARK: - Alert routing
    
    private func handleAlertTap(_ alert: ActionAlert) {
        switch alert.route {
        case .location(let id):
            if let loc = viewModel.locations.first(where: { $0.id == id }) {
                selectedLocationForAlert = loc
            }
        case .noAction:
            // MVP — schedule-gap alerts will route into the Employees tab
            // in a later phase. For now they're informational only.
            break
        }
    }
    
    // MARK: - Section dispatcher
    
    // Each case maps a HomeSection enum to its rendered subview. Driven
    // by `layoutStore.prefs.visibleSectionsInOrder` so the user's
    // toggle/reorder choices in Settings show up here without any
    // additional bookkeeping. New sections: add the case + the view.
    @ViewBuilder
    private func section(for sectionId: HomeSection) -> some View {
        switch sectionId {
        case .actionCenter:
            // Filter out any categories the user has hidden from
            // Settings → Home Layout → Needs Attention. Filtering happens
            // here (not in the view model) so toggling is instant — no
            // refetch — and the underlying data stays available for any
            // other surface that wants the unfiltered list.
            let visibleAlerts = alertsViewModel.alerts
                .filter { alert in
                    !layoutStore.prefs.hiddenAlertCategories.contains(alert.category)
                }
                .filteringAcknowledged(authViewModel.acknowledgedAlertIdSet)
            ActionCenterCard(
                alerts: visibleAlerts,
                isLoading: alertsViewModel.isLoading,
                onTapAlert: { alert in
                    handleAlertTap(alert)
                },
                onAcknowledge: { alert in
                    Task { await authViewModel.acknowledgeAlert(alert.id) }
                }
            )
            .padding(.horizontal)

        case .orgTodos:
            OrgTodosCard(viewModel: orgTodosViewModel)
                .padding(.horizontal)
            
        case .thisWeek:
            ThisWeekCard(
                pulse: alertsViewModel.weeklyPulse,
                onTapReceivables: { dueThisWeekKind = .receivables },
                onTapPayables: { dueThisWeekKind = .payables }
            )
            
        case .lotteryToday:
            LotteryTodayCard(
                rows: alertsViewModel.lotteryToday,
                onTapLocation: { locId in
                    if let loc = viewModel.locations.first(where: { $0.id == locId }) {
                        selectedLocationForAlert = loc
                    }
                }
            )
            
        case .shortcuts:
            shortcutsSection
            
        case .monthToDate:
            monthToDateSection
        }
    }
    
    // MARK: - Section subviews
    
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcuts")
                .font(.headline)
                .foregroundColor(.black)
                .padding(.horizontal)
            
            Button(action: { showingAllShifts = true }) {
                ShortcutCard(
                    icon: "clock.fill",
                    title: "Clock in Clock out data",
                    color: .green
                )
            }
            .padding(.horizontal)
            
            Button(action: { showingPayroll = true }) {
                ShortcutCard(
                    icon: "dollarsign.circle.fill",
                    title: "Payroll",
                    color: .blue
                )
            }
            .padding(.horizontal)
            
            Button(action: { showingAllStatus = true }) {
                ShortcutCard(
                    icon: "building.2.fill",
                    title: "All locations status",
                    color: .purple
                )
            }
            .padding(.horizontal)
            
            Button(action: { showingAnnouncement = true }) {
                ShortcutCard(
                    icon: "megaphone.fill",
                    title: "Send announcement",
                    color: .orange
                )
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private var monthToDateSection: some View {
        if !viewModel.locationStats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Month to Date")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal)
                
                ForEach(viewModel.locationStats) { stat in
                    LocationStatsCard(
                        stats: stat,
                        onViewHistory: {
                            if let loc = viewModel.locations.first(where: { $0.id == stat.id }) {
                                selectedLocation = loc
                            }
                        }
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
    }
}

// NOTE: a legacy `LocationCard` row used to live here. It was never
// wired up to anything (the manager dashboard renders the
// rainbow-gradient `LocationRow` in ManagerDashboardView.swift), so it
// was removed during the visual-unification pass to avoid misleading
// future readers.

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
        .oplixCard()
    }
}

struct LocationStatsCard: View {
    let stats: LocationStats
    // Optional callback: when set, an inline "View monthly history" link
    // appears at the bottom of the expanded card so the user can drill
    // into LocationMonthlyStatsView without bouncing back to a "Stats By
    // Month" section (which is no longer present on Home).
    var onViewHistory: (() -> Void)? = nil
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // COLLAPSED HEADER — tappable to expand. Shows the headline
            // number (total revenue) at a glance so the user can scan a
            // list of locations without expanding every one.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stats.locationName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        Text("Total sales this month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(formatCurrencyCompact(stats.monthToDateTotalRevenue))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider().padding(.horizontal)
                
                VStack(spacing: 8) {
                    // Headline total is merchandise/register only; fuel and
                    // lottery are tracked on their own rows below.
                    StatRow(
                        icon: "bag.fill",
                        label: "Merchandise (cash + credit)",
                        value: formatCurrency(stats.monthToDateSales),
                        color: .blue
                    )
                    StatRow(
                        icon: "fuelpump.fill",
                        label: "Fuel sales",
                        value: formatCurrency(stats.monthToDateFuelDollars),
                        color: .orange
                    )
                    StatRow(
                        icon: "ticket.fill",
                        label: "Lottery sales",
                        value: formatCurrency(stats.monthToDateLotterySales),
                        color: .purple
                    )
                    StatRow(
                        icon: "drop.fill",
                        label: "Fuel volume (gallons)",
                        value: String(format: "%.2f", stats.monthToDateFuelGallons),
                        color: .orange
                    )
                    Divider()
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
                    
                    if let onViewHistory = onViewHistory {
                        Divider()
                        Button(action: onViewHistory) {
                            HStack {
                                Text("View monthly history")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(Theme.cloudBlue)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .oplixCard()
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    // Compact format for the collapsed-row big number ("$24.3K" instead
    // of "$24,341.27") so a 3-location list stays scannable.
    private func formatCurrencyCompact(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = amount >= 1000 ? 1 : 2
        if amount >= 1000 {
            let k = amount / 1000.0
            return "$" + String(format: "%.1fK", k)
        }
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
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

/// Manager Home Quick Action tile (Clock data, Payroll, All locations
/// status, Send announcement). Delegates to the shared
/// `OplixActionTile` so the manager shortcuts match the
/// employee/supervisor home tab tiles and the Supervise screen.
struct ShortcutCard: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        OplixActionTile(icon: icon, title: title, color: color)
    }
}

#Preview {
    ManagerOverviewView(userId: "test-user")
}

