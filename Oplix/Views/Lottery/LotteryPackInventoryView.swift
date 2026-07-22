//
//  LotteryPackInventoryView.swift
//  Oplix
//

import SwiftUI

struct LotteryPackInventoryView: View {
    @StateObject private var viewModel: LotteryPackInventoryViewModel
    @State private var showingAssignSheet = false
    @State private var showingReceiveSheet = false
    @State private var showingReturnSheet = false
    @State private var showingMoveSheet = false
    @State private var stockPackToAssign: LotteryStockPack?

    init(managerUserId: String, location: Location) {
        _viewModel = StateObject(wrappedValue: LotteryPackInventoryViewModel(
            managerUserId: managerUserId,
            location: location
        ))
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.rackRows.isEmpty {
                ProgressView("Loading rack…")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard

                        if viewModel.hasMultipleTerminals {
                            terminalPicker
                        }

                        if let success = viewModel.successMessage {
                            Text(success)
                                .font(.subheadline)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }

                        stockSection

                        rackTable

                        packTalliesSection

                        if !viewModel.pendingReturns.isEmpty {
                            PackReturnsBreakdownView(
                                title: "Pending returns (next shift close)",
                                lines: viewModel.pendingReturnLineItems,
                                footerNote: pendingReturnsFooterNote
                            )
                            .padding(.horizontal)
                        }

                        if !viewModel.pendingCloseouts.isEmpty {
                            pendingCloseoutsSection
                        }

                        if !viewModel.appliedReturnHistory.isEmpty {
                            returnHistorySection
                        }

                        Button {
                            showingReceiveSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "tray.and.arrow.down.fill")
                                Text("Receive into stock")
                            }
                            .frame(maxWidth: .infinity)
                            .cloudButton(backgroundColor: .teal)
                        }
                        .padding(.horizontal)
                        .disabled(viewModel.isSaving)

                        Button {
                            showingAssignSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "barcode.viewfinder")
                                Text("Assign pack")
                            }
                            .frame(maxWidth: .infinity)
                            .cloudButton()
                        }
                        .padding(.horizontal)
                        .disabled(viewModel.isSaving)

                        Button {
                            showingReturnSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.uturn.backward.circle")
                                Text("Return pack")
                            }
                            .frame(maxWidth: .infinity)
                            .cloudButton(backgroundColor: .orange)
                        }
                        .padding(.horizontal)
                        .disabled(viewModel.isSaving)

                        Button {
                            showingMoveSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                Text("Move pack")
                            }
                            .frame(maxWidth: .infinity)
                            .cloudButton(backgroundColor: .blue)
                        }
                        .padding(.horizontal)
                        .disabled(viewModel.isSaving)
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Pack inventory")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadRack()
        }
        .refreshable {
            await viewModel.loadRack()
        }
        .sheet(isPresented: $showingReceiveSheet) {
            ReceiveLotteryPackSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAssignSheet) {
            AssignLotteryPackSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingReturnSheet) {
            ReturnLotteryPackSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveLotteryPackSheet(viewModel: viewModel)
        }
        .sheet(item: $stockPackToAssign) { pack in
            AssignStockPackSheet(viewModel: viewModel, pack: pack)
        }
        .overlay {
            if viewModel.isSaving {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("Saving…")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.location.name)
                .font(.title2.bold())
            Text("Stock inventory and active packs on the lottery rack")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var stockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In stock (not on a bin)")
                .font(.headline)
                .padding(.horizontal)

            if viewModel.stockPacks.isEmpty {
                Text("No packs in stock. Receive new books here, then assign to bins or scan at shift close.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.stockPacks) { pack in
                        Button {
                            stockPackToAssign = pack
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Game \(pack.gameNumber) · $\(pack.value) · \(pack.tickets) tk")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text("Pack \(pack.packSerial)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Assign")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.teal)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if pack.id != viewModel.stockPacks.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Theme.cloudWhite)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    private var terminalPicker: some View {
        Picker("Terminal", selection: Binding(
            get: { viewModel.selectedTerminal },
            set: { viewModel.selectTerminal($0) }
        )) {
            ForEach(viewModel.terminalNumbers, id: \.self) { n in
                Text("Terminal \(n)").tag(n)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var rackTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bin").frame(width: 36, alignment: .leading)
                Text("Game").frame(width: 52, alignment: .leading)
                Text("Pack").frame(minWidth: 72, alignment: .leading)
                Text("Status").frame(width: 64, alignment: .leading)
                Text("Begin").frame(width: 44, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.05))

            if viewModel.rackRows.isEmpty {
                Text("No bins configured yet. Set up the lottery template first.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
            } else {
                ForEach(viewModel.rackRows) { row in
                    HStack {
                        Text(row.binNumber)
                            .frame(width: 36, alignment: .leading)
                        Text(row.gameNumber.isEmpty ? "—" : row.gameNumber)
                            .frame(width: 52, alignment: .leading)
                        Text(row.packSerial ?? "—")
                            .lineLimit(1)
                            .frame(minWidth: 72, alignment: .leading)
                        Text(row.statusLabel)
                            .font(.caption)
                            .frame(width: 64, alignment: .leading)
                            .foregroundColor(statusColor(row))
                        Text(row.beginningNumber.isEmpty ? "—" : row.beginningNumber)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    Divider()
                }
            }
        }
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var pendingReturnsFooterNote: String {
        let deduct = viewModel.pendingReturnCloseDeductionDollars
        let gross = viewModel.pendingReturnDollars
        if abs(deduct - gross) < 0.005 {
            return "Applied automatically on the next lottery shift close."
        }
        return "Close will subtract \(formatCurrency(deduct)) (unsold returns with $0 sold are skipped). Gross returned face \(formatCurrency(gross))."
    }

    private var packTalliesSection: some View {
        HStack(spacing: 12) {
            tallyCard(
                title: "Returned",
                subtitle: "Applied history",
                count: viewModel.tallyReturnedPacks,
                dollars: viewModel.tallyReturnedDollars,
                accent: .orange
            )
            tallyCard(
                title: "Sold / finished",
                subtitle: "Pending close",
                count: viewModel.tallySoldFinishedPacks,
                dollars: viewModel.tallySoldFinishedDollars,
                accent: .green
            )
        }
        .padding(.horizontal)
    }

    private func tallyCard(
        title: String,
        subtitle: String,
        count: Int,
        dollars: Double,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(count) pack\(count == 1 ? "" : "s")")
                .font(.title3.weight(.bold))
                .foregroundColor(accent)
            Text(formatCurrency(dollars))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }

    private var pendingCloseoutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finished packs (next shift close)")
                .font(.headline)
            Text("+\(viewModel.pendingCloseoutTickets) tickets · \(formatCurrency(viewModel.pendingCloseoutDollars))")
                .font(.subheadline)
                .foregroundColor(.green)

            ForEach(viewModel.pendingCloseouts) { item in
                HStack {
                    Text("Bin \(item.binNumber)")
                    Spacer()
                    Text("\(item.beginningNumber)→\(item.endingNumber)")
                        .foregroundColor(.secondary)
                    Text("\(item.soldTickets) tk")
                        .foregroundColor(.secondary)
                    Text(formatCurrency(item.soldDollars))
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var returnHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Return history")
                .font(.headline)

            ForEach(viewModel.appliedReturnHistory) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Bin \(item.binNumber) · Game \(item.gameNumber)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(formatCurrency(item.returnedDollars))
                            .font(.subheadline.weight(.medium))
                    }
                    Text(historyDetailLine(for: item))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(statusDateLabel(for: item))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                if item.id != viewModel.appliedReturnHistory.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func statusDateLabel(for item: LotteryReturn) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let applied = item.appliedAt {
            return "Applied \(formatter.string(from: applied))"
        }
        return "Returned \(formatter.string(from: item.createdAt))"
    }

    private func historyDetailLine(for item: LotteryReturn) -> String {
        var parts: [String] = []
        let value = item.resolvedTicketValue.replacingOccurrences(of: "$", with: "")
        if !value.isEmpty { parts.append("$\(value)") }
        parts.append("\(item.returnedTickets) tk")
        if !item.packSerial.isEmpty { parts.append("Pack \(item.packSerial)") }
        if !item.ticketNumber.isEmpty { parts.append("top \(item.ticketNumber)") }
        return parts.joined(separator: " · ")
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func statusColor(_ row: LotteryPackRackRow) -> Color {
        switch row.packStatus {
        case .active: return .green
        case .returned: return .orange
        case .empty: return .secondary
        case nil:
            return row.packSerial == nil ? .secondary : .green
        }
    }
}
