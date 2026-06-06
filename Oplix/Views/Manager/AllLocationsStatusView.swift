//
//  AllLocationsStatusView.swift
//  Oplix
//
//  A single-screen overview of every location's CURRENT state — meant
//  to answer "how is each location doing right now" without expanding
//  individual MTD cards. Opened from the Home tab's Quick Actions.
//

import SwiftUI

struct AllLocationsStatusView: View {
    let userId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel

    @StateObject private var viewModel: AllLocationsStatusViewModel
    @State private var selectedLocation: Location?

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: AllLocationsStatusViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 0) {
                    headerBar

                    if viewModel.isLoading && viewModel.rows.isEmpty {
                        Spacer()
                        ProgressView().scaleEffect(1.5)
                        Spacer()
                    } else if viewModel.rows.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(viewModel.rows) { row in
                                    Button {
                                        selectedLocation = row.location
                                    } label: {
                                        statusRow(row)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                            .padding(.bottom, 40)
                        }
                        .refreshable {
                            await viewModel.load()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .task { await viewModel.load() }
            .fullScreenCover(item: $selectedLocation) { location in
                NavigationStack {
                    LocationDetailView(
                        userId: userId,
                        locationId: location.id,
                        showsCloseButton: true
                    )
                    .environmentObject(authViewModel)
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            Spacer()
            Text("All Locations")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.3, blue: 0.6),
                    Color(red: 0.15, green: 0.4, blue: 0.7)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.2.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.cloudBlue)
            Text("No locations yet")
                .font(.title3)
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Row

    private func statusRow(_ row: LocationStatusRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(row.location.name)
                    .font(.headline)
                    .foregroundColor(.black)

                if row.alertCount > 0 {
                    Text("\(row.alertCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }

                Spacer()

                // Live "someone is on shift" dot
                HStack(spacing: 4) {
                    Circle()
                        .fill(row.clockedInCount > 0 ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text("\(row.clockedInCount) on shift")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                miniMetric(
                    label: "TODAY",
                    primary: formatCurrencyCompact(row.todayRevenue),
                    color: .blue
                )
                miniMetric(
                    label: "TASKS",
                    primary: row.tasksTotal > 0 ? "\(Int(row.taskCompletionPct * 100))%" : "—",
                    color: .orange
                )
                miniMetric(
                    label: "MTD",
                    primary: formatCurrencyCompact(row.mtdRevenue),
                    color: .green
                )
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
    }

    private func miniMetric(label: String, primary: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text(primary)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }

    private func formatCurrencyCompact(_ amount: Double) -> String {
        if amount >= 1000 {
            return "$" + String(format: "%.1fK", amount / 1000.0)
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }
}

// MARK: - View Model

struct LocationStatusRow: Identifiable {
    let id: String
    let location: Location
    let clockedInCount: Int
    let todayRevenue: Double
    let mtdRevenue: Double
    let tasksCompleted: Int
    let tasksTotal: Int
    let alertCount: Int

    var taskCompletionPct: Double {
        guard tasksTotal > 0 else { return 0 }
        return Double(tasksCompleted) / Double(tasksTotal)
    }
}

@MainActor
final class AllLocationsStatusViewModel: ObservableObject {
    @Published private(set) var rows: [LocationStatusRow] = []
    @Published private(set) var isLoading = false

    private let userId: String
    private let firebaseService = FirebaseService.shared

    init(userId: String) { self.userId = userId }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let locations: [Location]
        let tasks: [WorkTask]
        do {
            locations = try await firebaseService.fetchLocations(userId: userId)
            tasks = try await firebaseService.fetchManagerTasks(userId: userId)
        } catch {
            rows = []
            return
        }

        // Fan out per-location fetches in parallel.
        var collected: [LocationStatusRow] = []
        await withTaskGroup(of: LocationStatusRow?.self) { group in
            for loc in locations {
                group.addTask { [weak self] in
                    await self?.buildRow(for: loc, allTasks: tasks)
                }
            }
            for await row in group {
                if let row = row { collected.append(row) }
            }
        }
        // Stable sort by name so the list doesn't reshuffle.
        rows = collected.sorted { $0.location.name < $1.location.name }
    }

    private func buildRow(for location: Location, allTasks: [WorkTask]) async -> LocationStatusRow? {
        async let shiftsT = firebaseService.fetchShifts(userId: userId, locationId: location.id)
        async let formsT = firebaseService.fetchLotteryForms(userId: userId, locationId: location.id)
        async let payablesT = firebaseService.fetchPayables(userId: userId, locationId: location.id)

        let shifts: [Shift]
        let forms: [LotteryForm]
        let payables: [Payable]
        do {
            shifts = try await shiftsT
            forms = try await formsT
            payables = try await payablesT
        } catch {
            return nil
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        var todayRevenue: Double = 0
        var mtdRevenue: Double = 0
        var clockedIn = 0

        for shift in shifts {
            if shift.isActive { clockedIn += 1 }
            guard shift.hasRegisterData,
                  let dateRef = shift.registerClosedAt ?? shift.clockOutTime else { continue }

            // Sum merchandise + fuel from registers (lottery added separately below).
            var shiftRev: Double = 0
            if !shift.registers.isEmpty {
                for r in shift.registers {
                    shiftRev += (r.cashSale ?? 0) + (r.creditCard ?? 0) + (r.fuelSaleDollars ?? 0)
                }
            } else {
                shiftRev += (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
            }
            if dateRef >= todayStart && dateRef < tomorrowStart { todayRevenue += shiftRev }
            if dateRef >= monthStart { mtdRevenue += shiftRev }
        }
        for form in forms {
            let amount = form.shiftSummary?.totalSoldAmount ?? 0
            if form.submittedAt >= todayStart && form.submittedAt < tomorrowStart { todayRevenue += amount }
            if form.submittedAt >= monthStart { mtdRevenue += amount }
        }

        // Tasks for this location
        let locationTasks = allTasks.filter { $0.locationId == location.id }
        let tasksCompleted = locationTasks.reduce(0) { acc, task in
            acc + (task.currentCycleCompletions.values.contains { $0.countsAsCompleted } ? 1 : 0)
        }

        // Alert count = overdue payables for this location (simple proxy
        // matching the Locations tab badge).
        let overdueCount = payables.filter { p in
            guard !p.isPaid, let due = p.dueDate else { return false }
            return calendar.startOfDay(for: due) < todayStart
        }.count

        return LocationStatusRow(
            id: location.id,
            location: location,
            clockedInCount: clockedIn,
            todayRevenue: todayRevenue,
            mtdRevenue: mtdRevenue,
            tasksCompleted: tasksCompleted,
            tasksTotal: locationTasks.count,
            alertCount: overdueCount
        )
    }
}
