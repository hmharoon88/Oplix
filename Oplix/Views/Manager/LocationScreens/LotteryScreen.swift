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
                                CollapsibleDateSection(dateKey: dateKey, forms: groupedForms[dateKey] ?? [], viewModel: viewModel)
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
        .onAppear {
            Task {
                await viewModel.loadData()
            }
        }
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
                
                Text(formatTime(form.submittedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Lottery Form Data Table
            if let template = template, !template.rows.isEmpty {
                VStack(spacing: 0) {
                    // Header Row
                    HStack(spacing: 0) {
                        headerCell("Bin #")
                        headerCell("Value")
                        headerCell("Begin #")
                        headerCell("End #")
                    }
                    .background(Theme.cloudBlue.opacity(0.2))
                    
                    // Data Rows
                    ForEach(Array(template.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 0) {
                            binNumberCell(String(index + 1))
                            readOnlyCell(formatValue(row.value))
                            readOnlyCell(row.beginningNumber)
                            // Get ending number from form data
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
                .padding(.vertical, 8)
            } else if isLoadingTemplate {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            
            // Shift Summary Report (if available)
            if let summary = form.shiftSummary {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Shift Summary Report")
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    // Template Totals
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
                    
                    // Sales Summary
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sales Summary")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        SummaryRow(label: "Instant Total", value: formatCurrency(summary.instantTotal))
                        SummaryRow(label: "Online Total", value: formatCurrency(summary.onlineTotal))
                        SummaryRow(label: "Total Sold Amount", value: formatCurrency(summary.totalSoldAmount))
                    }
                    
                    Divider()
                    
                    // Cash Summary
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cash Summary")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        SummaryRow(label: "Register Cash", value: formatCurrency(summary.registerCash))
                        SummaryRow(label: "Total Cash", value: formatCurrency(summary.totalCash))
                        SummaryRow(label: "Online Cashes", value: formatCurrency(summary.onlineCashes))
                        SummaryRow(label: "Instant Cashes", value: formatCurrency(summary.instantCashes))
                        SummaryRow(label: "Total Cashes", value: formatCurrency(summary.totalCashes))
                        
                        Divider()
                        
                        SummaryRow(label: "Remaining Cash", value: formatCurrency(summary.cashInBag))
                            .font(.headline)
                        SummaryRow(label: "Shift End Cash", value: formatCurrency(summary.cashInBagNet))
                            .font(.headline)
                            .foregroundColor(summary.cashInBagNet >= 0 ? .green : .red)
                        
                        // Over/Short (if available)
                        if let overShort = summary.overShort {
                            Divider()
                            SummaryRow(
                                label: overShort >= 0 ? "Over" : "Short",
                                value: formatCurrency(overShort)
                            )
                            .font(.headline)
                            .foregroundColor(overShort >= 0 ? .green : .red)
                        }
                    }
                }
                .padding()
                .background(Color(red: 0.95, green: 0.95, blue: 1.0))
                .cornerRadius(12)
            }
            
            // Form Data Summary (fallback if no summary)
            if form.shiftSummary == nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let onlineTotal = getFormValue(key: "online_total_0") {
                        SummaryRow(label: "Online Total", value: onlineTotal)
                    }
                    
                    if let onlineCash = getFormValue(key: "online_cash_0") {
                        SummaryRow(label: "Online Cash", value: onlineCash)
                    }
                    
                    if let instantCash = getFormValue(key: "instant_cash_0") {
                        SummaryRow(label: "Instant Cash", value: instantCash)
                    }
                    
                    // Show additional entries if they exist
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
            }
            
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
    
    private func loadTemplate() {
        guard template == nil && !isLoadingTemplate else { return }
        isLoadingTemplate = true
        
        Task {
            do {
                if let fetchedTemplate = try await FirebaseService.shared.fetchLotteryFormTemplate(userId: viewModel.userId, locationId: form.locationId) {
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
    
    private func getEndingNumber(for rowId: String) -> String {
        // Form data stores ending numbers with key "row_\(rowId)"
        let key = "row_\(rowId)"
        if let endingNumber = form.formData[key], !endingNumber.isEmpty {
            return endingNumber
        }
        // Fall back to template if not in form data
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

// Collapsible date section
struct CollapsibleDateSection: View {
    let dateKey: String
    let forms: [LotteryForm]
    let viewModel: LocationDetailViewModel
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Date header (always visible)
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
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

