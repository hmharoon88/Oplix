//
//  InvoicesListView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct InvoicesListView: View {
    let userId: String
    @StateObject private var viewModel: InvoicesViewModel
    @State private var showingAddInvoice = false
    @State private var selectedInvoice: Invoice?
    @State private var showingPayInvoice = false
    
    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: InvoicesViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                        Text("Oplix")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            showingAddInvoice = true
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
                    
                    // Content
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                // Summary Cards
                                HStack(spacing: 16) {
                                    InvoiceSummaryCard(
                                        title: "Unpaid",
                                        count: viewModel.unpaidInvoices.count,
                                        total: viewModel.unpaidTotal,
                                        color: .red
                                    )
                                    
                                    InvoiceSummaryCard(
                                        title: "Paid",
                                        count: viewModel.paidInvoices.count,
                                        total: viewModel.paidTotal,
                                        color: .green
                                    )
                                }
                                .padding(.horizontal)
                                .padding(.top, 20)
                                
                                // Unpaid Invoices Section
                                if !viewModel.unpaidInvoices.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Unpaid Invoices")
                                            .font(.headline)
                                            .foregroundColor(.black)
                                            .padding(.horizontal)
                                        
                                        ForEach(viewModel.unpaidInvoices) { invoice in
                                            InvoiceCard(invoice: invoice) {
                                                selectedInvoice = invoice
                                                showingPayInvoice = true
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                                
                                // Paid Invoices Section
                                if !viewModel.paidInvoices.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Paid Invoices")
                                            .font(.headline)
                                            .foregroundColor(.black)
                                            .padding(.horizontal)
                                        
                                        ForEach(viewModel.paidInvoices) { invoice in
                                            InvoiceCard(invoice: invoice, isPaid: true)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                                
                                if viewModel.invoices.isEmpty {
                                    VStack(spacing: 20) {
                                        Image(systemName: "doc.text.fill")
                                            .font(.system(size: 60))
                                            .foregroundColor(Theme.darkGray)
                                        Text("No Invoices")
                                            .font(.title2)
                                            .foregroundColor(Theme.darkGray)
                                        Text("Tap the + button to add an invoice")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 60)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Invoices")
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
                await viewModel.loadInvoices()
            }
            .sheet(isPresented: $showingAddInvoice) {
                AddInvoiceView(userId: userId, locationId: nil) {
                    Task {
                        await viewModel.loadInvoices()
                    }
                }
            }
            .sheet(item: $selectedInvoice) { invoice in
                PayInvoiceView(userId: userId, invoice: invoice) {
                    Task {
                        await viewModel.loadInvoices()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }
}

struct InvoiceSummaryCard: View {
    let title: String
    let count: Int
    let total: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("\(count)")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
            
            Text(formatCurrency(total))
                .font(.headline)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
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

struct InvoiceCard: View {
    let invoice: Invoice
    var isPaid: Bool = false
    var onPay: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatCurrency(invoice.amount))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text(invoice.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Text(formatDate(invoice.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let fileURL = invoice.fileURL {
                    if let fileType = invoice.fileType, ["jpg", "jpeg", "png", "gif"].contains(fileType.lowercased()) {
                        // Display image
                        AsyncImage(url: URL(string: fileURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                    } else {
                        // Display file icon
                        Link(destination: URL(string: fileURL)!) {
                            VStack {
                                Image(systemName: iconForFileType(invoice.fileType ?? "pdf"))
                                    .font(.system(size: 30))
                                    .foregroundColor(.blue)
                                if let fileName = invoice.fileName {
                                    Text(fileName)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 80, height: 80)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                } else {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                        .frame(width: 80, height: 80)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            if isPaid, let paidAt = invoice.paidAt, let paidBy = invoice.paidBy, let paymentMethod = invoice.paymentMethod {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Paid on \(formatDate(paidAt)) by \(paidBy) via \(paymentMethod.rawValue)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else if !isPaid {
                Button(action: {
                    onPay?()
                }) {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("Mark as Paid")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func iconForFileType(_ fileType: String?) -> String {
        guard let fileType = fileType else { return "doc.fill" }
        let type = fileType.lowercased()
        if type == "pdf" {
            return "doc.fill"
        } else if ["xlsx", "xls"].contains(type) {
            return "tablecells.fill"
        } else if ["jpg", "jpeg", "png", "gif"].contains(type) {
            return "photo.fill"
        } else {
            return "doc.fill"
        }
    }
}

@MainActor
class InvoicesViewModel: ObservableObject {
    @Published var invoices: [Invoice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingError = false
    
    private let firebaseService = FirebaseService.shared
    let userId: String
    let locationId: String?
    
    init(userId: String, locationId: String? = nil) {
        self.userId = userId
        self.locationId = locationId
    }
    
    var unpaidInvoices: [Invoice] {
        invoices.filter { !$0.isPaid }
    }
    
    var paidInvoices: [Invoice] {
        invoices.filter { $0.isPaid }
    }
    
    var unpaidTotal: Double {
        unpaidInvoices.reduce(0) { $0 + $1.amount }
    }
    
    var paidTotal: Double {
        paidInvoices.reduce(0) { $0 + $1.amount }
    }
    
    func loadInvoices() async {
        isLoading = true
        errorMessage = nil
        
        do {
            invoices = try await firebaseService.fetchInvoices(userId: userId, locationId: locationId)
        } catch {
            errorMessage = "Failed to load invoices: \(error.localizedDescription)"
            showingError = true
        }
        
        isLoading = false
    }
}

