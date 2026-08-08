//
//  LotteryScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var showingCustomization = false
    @State private var showingGameDatabase = false
    @State private var openedLotteryDateKeys: Set<String> = []
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Customization Placeholder
                    Button(action: {
                        showingCustomization = true
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 50))
                                .foregroundColor(Theme.cloudBlue)
                            
                            Text("Customization")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text("Configure lottery form template")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(Theme.cloudWhite)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    
                    // Game Database Placeholder
                    Button(action: {
                        showingGameDatabase = true
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "database")
                                .font(.system(size: 50))
                                .foregroundColor(Theme.cloudBlue)
                            
                            Text("Game Database")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text("Manage global game data")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(Theme.cloudWhite)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)

                    // Pack inventory
                    if let location = viewModel.location {
                        NavigationLink {
                            LotteryPackInventoryView(managerUserId: viewModel.userId, location: location)
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.orange)

                                Text("Pack inventory")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)

                                Text("View rack and assign packs to bins")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(Theme.cloudWhite)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }

                    // Previous Shifts
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Previous Shifts")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.horizontal)
                        
                        if viewModel.lotteryForms.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 50))
                                    .foregroundColor(Theme.cloudBlue)
                                
                                Text("No Previous Shifts")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Lottery shift summaries will appear here")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(Theme.cloudWhite)
                            .cornerRadius(16)
                            .padding(.horizontal)
                        } else {
                            // Sort forms by date (newest first) before grouping
                            let sortedForms = viewModel.lotteryForms.sorted { $0.submittedAt > $1.submittedAt }
                            
                            // Group forms by date
                            let groupedForms = groupFormsByDate(sortedForms)
                            
                            // Sort date keys by converting to dates for proper chronological sorting
                            let sortedDateKeys = groupedForms.keys.sorted { dateKey1, dateKey2 in
                                if let date1 = parseDateKey(dateKey1), let date2 = parseDateKey(dateKey2) {
                                    return date1 > date2
                                }
                                return dateKey1 > dateKey2 // Fallback to string comparison
                            }
                            
                            ForEach(sortedDateKeys, id: \.self) { dateKey in
                                CollapsibleDateSection(
                                    dateKey: dateKey,
                                    forms: groupedForms[dateKey] ?? [],
                                    viewModel: viewModel,
                                    isDateOpened: openedLotteryDateKeys.contains(dateKey),
                                    onDateOpened: { markLotteryDateOpened(dateKey) }
                                )
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Lottery")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $showingCustomization) {
            LotteryCustomizationView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingGameDatabase) {
            GameDatabaseView()
        }
        .task {
            await viewModel.loadData()
            refreshOpenedLotteryDates()
        }
        .onChange(of: viewModel.lotteryForms.count) { _, _ in
            refreshOpenedLotteryDates()
        }
    }

    private var lotteryPrefsLocationId: String {
        viewModel.location?.id ?? viewModel.lotteryForms.first?.locationId ?? ""
    }

    private func refreshOpenedLotteryDates() {
        let locId = lotteryPrefsLocationId
        guard !locId.isEmpty else { return }
        openedLotteryDateKeys = LotteryOpenedDatesStore.load(locationId: locId)
    }

    private func markLotteryDateOpened(_ dateKey: String) {
        let locId = lotteryPrefsLocationId
        guard !locId.isEmpty else { return }
        guard openedLotteryDateKeys.insert(dateKey).inserted else { return }
        LotteryOpenedDatesStore.save(openedLotteryDateKeys, locationId: locId)
    }
}

struct PreviousLotteryShiftCard: View {
    let form: LotteryForm
    let viewModel: LocationDetailViewModel
    @State private var image: UIImage?
    @State private var isLoadingImage = false
    @State private var template: LotteryFormTemplate?
    @State private var isLoadingTemplate = false
    @State private var showingFullScreenImage = false
    @State private var isBinTableExpanded = false

    /// Whether this card belongs to a multi-terminal location. Used
    /// only to drive whether we render a "Terminal N" badge — for
    /// single-terminal locations the card looks exactly as it did
    /// before multi-terminal support shipped (no badge).
    private var showsTerminalLabel: Bool {
        viewModel.location?.hasMultipleLotteryTerminals ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with date
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lottery Shift")
                        .font(.headline)
                        .foregroundColor(.black)

                    Text(formatDate(form.submittedAt))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if showsTerminalLabel {
                    // Terminal badge sits between the title and the
                    // time. Always renders for multi-terminal locations
                    // even on legacy submissions (where terminalNumber
                    // is nil) — those are shown as Terminal 1, which
                    // matches how they're stored under doc id `template`.
                    Text("Terminal \(form.effectiveTerminalNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.cloudBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.cloudBlue.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(formatTime(form.submittedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()

            shiftSummarySection

            legacyFormDataSection

            collapsibleBinTableSection

            // Image if available
            if let imageURL = form.formData["imageURL"], !imageURL.isEmpty {
                if isLoadingImage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                } else if let image = image {
                    Button(action: {
                        showingFullScreenImage = true
                    }) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Placeholder while loading
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 200)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            if let imageURL = form.formData["imageURL"], !imageURL.isEmpty {
                loadImage(from: imageURL)
            }
            loadTemplate()
        }
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let imageURL = form.formData["imageURL"], !imageURL.isEmpty {
                TaskImageView(imageURL: imageURL, timestamp: form.submittedAt, employeeName: nil)
            }
        }
    }
    
    @ViewBuilder
    private var shiftSummarySection: some View {
        if let summary = form.shiftSummary {
            VStack(alignment: .leading, spacing: 12) {
                Text("Shift Summary")
                    .font(.headline)
                    .foregroundColor(.black)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Lottery Form Totals")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    SummaryRow(label: "Total Sold Tickets", value: "\(summary.totalSold)")
                    SummaryRow(label: "Total Dollars", value: formatCurrency(summary.totalDollars))
                    SummaryRow(label: "Total Books", value: "\(summary.totalBooks)")
                }

                Divider()

                LotteryCashFlowSummaryView(summary: summary)

                if let returns = summary.packReturns, !returns.isEmpty {
                    PackReturnsBreakdownView(
                        title: "Pack returns this close",
                        lines: returns
                    )
                }
            }
            .padding(.horizontal, 0)
        }
    }

    @ViewBuilder
    private var legacyFormDataSection: some View {
        if form.shiftSummary == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shift Data")
                    .font(.headline)
                    .foregroundColor(.black)

                if let onlineTotal = getFormValue(key: "online_total_0") {
                    SummaryRow(label: "Online Total", value: onlineTotal)
                }

                if let onlineCash = getFormValue(key: "online_cash_0") {
                    SummaryRow(label: "Online Cash", value: onlineCash)
                }

                if let instantCash = getFormValue(key: "instant_cash_0") {
                    SummaryRow(label: "Instant Cash", value: instantCash)
                }

                let additionalOnlineTotals = getAllFormValues(prefix: "online_total_")
                let additionalOnlineCashes = getAllFormValues(prefix: "online_cash_")
                let additionalInstantCashes = getAllFormValues(prefix: "instant_cash_")

                ForEach(Array(additionalOnlineTotals.enumerated()), id: \.offset) { index, value in
                    if index > 0 {
                        SummaryRow(label: "Online Total \(index + 1)", value: value)
                    }
                }

                ForEach(Array(additionalOnlineCashes.enumerated()), id: \.offset) { index, value in
                    if index > 0 {
                        SummaryRow(label: "Online Cash \(index + 1)", value: value)
                    }
                }

                ForEach(Array(additionalInstantCashes.enumerated()), id: \.offset) { index, value in
                    if index > 0 {
                        SummaryRow(label: "Instant Cash \(index + 1)", value: value)
                    }
                }
            }
            .padding()
            .background(Color(red: 0.95, green: 0.95, blue: 1.0))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var collapsibleBinTableSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isBinTableExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Bin, value, begin & end numbers")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.cloudBlue)
                        .rotationEffect(.degrees(isBinTableExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isBinTableExpanded {
                if let template = template, !template.rows.isEmpty {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            headerCell("Bin #")
                            headerCell("Value")
                            headerCell("Begin #")
                            headerCell("End #")
                        }
                        .background(Theme.cloudBlue.opacity(0.2))

                        ForEach(Array(template.rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 0) {
                                binNumberCell(String(index + 1))
                                readOnlyCell(formatValue(row.value))
                                readOnlyCell(beginningNumberForHistory(for: row.id))
                                readOnlyCell(getEndingNumber(for: row.id))
                            }
                            .background(index % 2 == 0 ? Theme.cloudWhite : Color.white)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .bottom
                            )
                        }
                    }
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(.gray.opacity(0.5)),
                        alignment: .leading
                    )
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(.gray.opacity(0.5)),
                        alignment: .trailing
                    )
                    .cornerRadius(8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if isLoadingTemplate {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    Text("No book rows configured for this terminal.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func loadTemplate() {
        guard template == nil && !isLoadingTemplate else { return }
        isLoadingTemplate = true

        Task {
            do {
                // Fetch the template for the terminal this form belongs
                // to. Legacy single-terminal forms have `terminalNumber`
                // == nil, which the FirebaseService treats as terminal 1
                // and reads from the legacy `template` doc — identical
                // to the original wire call.
                let fetchedTemplate = try await FirebaseService.shared.fetchLotteryFormTemplate(
                    userId: viewModel.userId,
                    locationId: form.locationId,
                    terminalNumber: form.terminalNumber
                )
                if let fetchedTemplate = fetchedTemplate {
                    await MainActor.run {
                        self.template = fetchedTemplate
                        self.isLoadingTemplate = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoadingTemplate = false
                    }
                }
            } catch {
                print("Failed to load lottery template: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoadingTemplate = false
                }
            }
        }
    }
    
    /// Opening numbers for *this* submitted shift (prefer snapshot on the form).
    private func beginningNumberForHistory(for rowId: String) -> String {
        let key = "begin_\(rowId)"
        if let b = form.formData[key], !b.isEmpty {
            return b
        }
        return template?.rows.first { $0.id == rowId }?.beginningNumber ?? ""
    }

    private func getEndingNumber(for rowId: String) -> String {
        let key = "row_\(rowId)"
        if let endingNumber = form.formData[key], !endingNumber.isEmpty {
            return endingNumber
        }
        return template?.rows.first { $0.id == rowId }?.endingNumber ?? ""
    }
    
    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.cloudBlue.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func binNumberCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func readOnlyCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func formatValue(_ value: String) -> String {
        if value.isEmpty {
            return ""
        }
        let cleanValue = value.replacingOccurrences(of: "$", with: "")
        return cleanValue.isEmpty ? "" : "$\(cleanValue)"
    }
    
    private func getFormValue(key: String) -> String? {
        let value = form.formData[key]
        return value?.isEmpty == false ? value : nil
    }
    
    private func getAllFormValues(prefix: String) -> [String] {
        var values: [String] = []
        var index = 0
        while let value = form.formData["\(prefix)\(index)"], !value.isEmpty {
            values.append(value)
            index += 1
        }
        return values
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func loadImage(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        isLoadingImage = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.image = uiImage
                        self.isLoadingImage = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoadingImage = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    var font: Font = .subheadline
    var foregroundColor: Color = .black
    
    var body: some View {
        HStack {
            Text(label)
                .font(font)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(font)
                .fontWeight(.medium)
                .foregroundColor(foregroundColor)
        }
    }
}

extension PreviousLotteryShiftCard {
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func formatCurrency(_ amount: Int) -> String {
        return formatCurrency(Double(amount))
    }
}

// Helper function to group forms by date
private func groupFormsByDate(_ forms: [LotteryForm]) -> [String: [LotteryForm]] {
    var grouped: [String: [LotteryForm]] = [:]
    
    for form in forms {
        let dateKey = formatDateKey(form.submittedAt)
        if grouped[dateKey] == nil {
            grouped[dateKey] = []
        }
        grouped[dateKey]?.append(form)
    }
    
    // Sort forms within each date group by time (newest first)
    for key in grouped.keys {
        grouped[key]?.sort { $0.submittedAt > $1.submittedAt }
    }
    
    return grouped
}

private func formatDateKey(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

private func parseDateKey(_ dateKey: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.date(from: dateKey)
}

// Persists which Previous Shifts date sections the manager has expanded.
enum LotteryOpenedDatesStore {
    private static func key(locationId: String) -> String {
        "lotteryOpenedDateKeys_\(locationId)"
    }

    static func load(locationId: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key(locationId: locationId)) ?? [])
    }

    static func save(_ opened: Set<String>, locationId: String) {
        UserDefaults.standard.set(Array(opened), forKey: key(locationId: locationId))
    }
}

// Collapsible date section
struct CollapsibleDateSection: View {
    let dateKey: String
    let forms: [LotteryForm]
    let viewModel: LocationDetailViewModel
    let isDateOpened: Bool
    let onDateOpened: () -> Void
    @State private var isExpanded = false

    private var showsUnreadDot: Bool {
        !isDateOpened
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Date header (always visible)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    let willExpand = !isExpanded
                    isExpanded = willExpand
                    if willExpand {
                        onDateOpened()
                    }
                }
            }) {
                HStack(spacing: 10) {
                    if showsUnreadDot {
                        Circle()
                            .fill(Theme.cloudBlue)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Not reviewed yet")
                    }

                    Text(dateKey)
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Text("\(forms.count) shift\(forms.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding()
                .background(Theme.cloudWhite)
            }
            .buttonStyle(.plain)
            
            // Forms (collapsible)
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(forms) { form in
                        PreviousLotteryShiftCard(form: form, viewModel: viewModel)
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

