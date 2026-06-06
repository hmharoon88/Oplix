//
//  InvoicesScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct InvoicesScreen: View {
    let userId: String
    let locationId: String
    @StateObject private var viewModel: InvoicesViewModel
    @State private var showingAddInvoice = false
    @State private var selectedInvoice: Invoice?
    @State private var showingPayInvoice = false
    
    init(userId: String, locationId: String) {
        self.userId = userId
        self.locationId = locationId
        _viewModel = StateObject(wrappedValue: InvoicesViewModel(userId: userId, locationId: locationId))
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading invoices...")
                        .foregroundColor(Theme.darkGray)
                }
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
                                    InvoiceCard(
                                        invoice: invoice,
                                        isPaid: false,
                                        onPay: {
                                            selectedInvoice = invoice
                                            showingPayInvoice = true
                                        }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // Paid Invoices Section
                        if !viewModel.paidInvoices.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Paid Invoices")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                                
                                ForEach(viewModel.paidInvoices) { invoice in
                                    InvoiceCard(
                                        invoice: invoice,
                                        isPaid: true,
                                        onPay: nil
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        if viewModel.unpaidInvoices.isEmpty && viewModel.paidInvoices.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(Theme.darkGray)
                                Text("No Invoices")
                                    .font(.title2)
                                    .foregroundColor(Theme.darkGray)
                                Text("No invoices found for this location")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.darkGray)
                            }
                            .padding(.top, 40)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddInvoice = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.cloudBlue)
                }
            }
        }
        .sheet(isPresented: $showingAddInvoice) {
            AddInvoiceView(userId: userId, locationId: locationId) {
                Task {
                    await viewModel.loadInvoices()
                }
            }
        }
        .sheet(isPresented: $showingPayInvoice) {
            if let invoice = selectedInvoice {
                PayInvoiceView(userId: userId, invoice: invoice) {
                    Task {
                        await viewModel.loadInvoices()
                    }
                }
            }
        }
        .task {
            await viewModel.loadInvoices()
        }
    }
}

