//
//  MultiTerminalLotterySheet.swift
//  Oplix
//
//  Multi-terminal close-out flow. Single-terminal locations never
//  reach this code — they continue to route through the legacy
//  `EmployeeLotteryFormSheet` / `LastShiftSummarySheet` exactly as
//  before. This file is the entire surface area added for locations
//  that are configured with `Location.lotteryTerminalCount > 1`.
//

import SwiftUI

// MARK: - Active Shift: Tabbed close-out per terminal

/// Tabbed close-out sheet shown when a multi-terminal location's
/// employee taps "Active Shift". One tab per active terminal — the
/// employee picks which terminals they actually worked and submits
/// each one independently. Untouched terminals stay untouched, so
/// their beginning numbers carry over to the next shift unchanged
/// ("skip allowed", per planning).
struct MultiTerminalLotteryFormSheet: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTerminal: Int = 1

    /// Active terminal numbers (configured count minus archived). We
    /// re-read from the location each render so changing terminal
    /// count from another device flows in via the snapshot listener.
    private var activeTerminals: [Int] {
        let location = viewModel.location
        let archived = Set(location?.lotteryArchivedTerminals ?? [])
        let count = location?.effectiveLotteryTerminalCount ?? 1
        return (1...count).filter { !archived.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Terminal picker — looks like the manager-side tab
                    // strip so the visual language is consistent
                    // between customization and close-out.
                    terminalPicker

                    // Active terminal's form. Hosting it inside a
                    // TabView gives free-side swipe between terminals
                    // while preserving each tab's local state (the
                    // .tag(...) value drives identity).
                    TabView(selection: $selectedTerminal) {
                        ForEach(activeTerminals, id: \.self) { terminal in
                            terminalForm(terminal: terminal)
                                .tag(terminal)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Lottery — Terminal \(selectedTerminal)")
                        .font(.headline)
                        .foregroundColor(.black)
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await viewModel.loadLotteryTemplate()
        }
        .onAppear {
            // Default to the first active terminal so the picker has
            // a valid initial selection even after archives change.
            if let first = activeTerminals.first {
                selectedTerminal = first
            }
        }
    }

    private var terminalPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeTerminals, id: \.self) { terminal in
                    Button(action: { selectedTerminal = terminal }) {
                        let isSelected = terminal == selectedTerminal
                        Text("Terminal \(terminal)")
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .white : Theme.cloudBlue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Theme.cloudBlue : Color.white.opacity(0.85))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.15))
    }

    @ViewBuilder
    private func terminalForm(terminal: Int) -> some View {
        if let template = viewModel.lotteryTemplates[terminal], !template.rows.isEmpty {
            // Reuse the existing single-terminal form view verbatim —
            // we only thread `terminalNumber` through so its writes
            // hit the right template / form doc.
            EmployeeLotteryFormView(
                viewModel: viewModel,
                template: template,
                terminalNumber: terminal
            )
            .background(Theme.cloudWhite)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 50))
                    .foregroundColor(Theme.darkGray)
                Text("Terminal \(terminal) is not configured")
                    .font(.headline)
                    .foregroundColor(Theme.darkGray)
                Text("Manager hasn't set up rows for this terminal yet.")
                    .font(.subheadline)
                    .foregroundColor(Theme.darkGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.cloudWhite)
        }
    }
}

// MARK: - Last Shift: stacked per-terminal summary

/// Last-shift summary for multi-terminal locations. Pulls every
/// `LotteryForm` written under the same `shiftId` as the most-recent
/// submission and renders one summary card per terminal.
struct LastShiftMultiTerminalSummarySheet: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    /// The most recent form for the location, used to anchor which
    /// shift's submissions we want to display.
    let anchorForm: LotteryForm
    @Environment(\.dismiss) private var dismiss

    @State private var formsByTerminal: [(terminal: Int, form: LotteryForm)] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading…")
                        .tint(.white)
                        .foregroundColor(.white)
                } else if formsByTerminal.isEmpty {
                    Text("No previous shift data")
                        .foregroundColor(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(formsByTerminal, id: \.form.id) { entry in
                                terminalCard(entry: entry)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Last Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
        }
    }

    @ViewBuilder
    private func terminalCard(entry: (terminal: Int, form: LotteryForm)) -> some View {
        let terminal = entry.terminal
        let summary = entry.form.shiftSummary

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundColor(Theme.cloudBlue)
                Text("Terminal \(terminal)")
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                Text(formatDate(entry.form.submittedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.cloudBlue.opacity(0.1))

            Divider()

            if let summary = summary {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow("Total Sold Tickets", value: "\(summary.totalSold)")
                    summaryRow("Total Dollars", value: formatCurrency(Double(summary.totalDollars)))
                    summaryRow("Total Books", value: "\(summary.totalBooks)")
                    Divider()
                    summaryRow("Instant Total", value: formatCurrency(summary.instantTotal))
                    summaryRow("Online Total", value: formatCurrency(summary.onlineTotal))
                    summaryRow("Total Sold Amount", value: formatCurrency(summary.totalSoldAmount))
                    Divider()
                    summaryRow("Register Cash", value: formatCurrency(summary.registerCash))
                    summaryRow("Total Cash", value: formatCurrency(summary.totalCash))
                    summaryRow("Cash In Bag", value: formatCurrency(summary.cashInBag), highlighted: true)
                    summaryRow("Shift End Cash", value: formatCurrency(summary.cashInBagNet), highlighted: true)
                    if let overShort = summary.overShort {
                        summaryRow("Over/Short", value: formatCurrency(overShort), highlighted: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Text("No summary recorded for this terminal.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(16)
            }
        }
        .background(Theme.cloudWhite)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    private func summaryRow(_ label: String, value: String, highlighted: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(highlighted ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundColor(.black)
            Spacer()
            Text(value)
                .font(highlighted ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundColor(.black)
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

    private func load() async {
        guard let managerUserId = viewModel.managerUserId else {
            isLoading = false
            return
        }
        do {
            let allForms = try await FirebaseService.shared.fetchLotteryForms(
                userId: managerUserId,
                locationId: viewModel.locationId
            )
            // The "last shift" group is every form sharing the
            // anchor's shiftId — that's how we tie multiple terminal
            // submissions together for the same close-out event.
            let group = allForms.filter { $0.shiftId == anchorForm.shiftId }
            let sorted = group
                .sorted { $0.effectiveTerminalNumber < $1.effectiveTerminalNumber }
                .map { (terminal: $0.effectiveTerminalNumber, form: $0) }
            await MainActor.run {
                formsByTerminal = sorted
                isLoading = false
            }
        } catch {
            print("Failed to load multi-terminal last shift: \(error.localizedDescription)")
            await MainActor.run { isLoading = false }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
