//
//  PayInvoiceView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct PayInvoiceView: View {
    let userId: String
    let invoice: Invoice
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var paidBy: String = ""
    @State private var paymentMethod: Invoice.PaymentMethod = .cash
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Invoice Details") {
                        HStack {
                            Text("Amount:")
                            Spacer()
                            Text(formatCurrency(invoice.amount))
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Text("Description:")
                            Spacer()
                            Text(invoice.description)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Created:")
                            Spacer()
                            Text(formatDate(invoice.createdAt))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let fileURL = invoice.fileURL {
                        Section("Invoice File") {
                            if let fileType = invoice.fileType, ["jpg", "jpeg", "png", "gif"].contains(fileType.lowercased()) {
                                // Display image
                                AsyncImage(url: URL(string: fileURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(maxHeight: 300)
                                .cornerRadius(8)
                            } else {
                                // Display file link
                                VStack(spacing: 12) {
                                    Image(systemName: iconForFileType(invoice.fileType ?? "pdf"))
                                        .font(.system(size: 60))
                                        .foregroundColor(.blue)
                                    
                                    if let fileName = invoice.fileName {
                                        Text(fileName)
                                            .font(.headline)
                                            .foregroundColor(.black)
                                    }
                                    
                                    Link(destination: URL(string: fileURL)!) {
                                        HStack {
                                            Image(systemName: "arrow.down.circle.fill")
                                            Text("Download File")
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Section("Payment Information") {
                        TextField("Paid By", text: $paidBy)
                            .placeholder(when: paidBy.isEmpty) {
                                Text("Enter name of person paying")
                                    .foregroundColor(.secondary)
                            }
                        
                        Picker("Payment Method", selection: $paymentMethod) {
                            ForEach([Invoice.PaymentMethod.cash, Invoice.PaymentMethod.check], id: \.self) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                    }
                    
                    Section {
                        Button(action: {
                            Task {
                                await markAsPaid()
                            }
                        }) {
                            if isSaving {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            } else {
                                Text("Mark as Paid")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(paidBy.isEmpty || isSaving)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Pay Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func markAsPaid() async {
        isSaving = true
        errorMessage = nil
        
        do {
            let updatedInvoice = Invoice(
                id: invoice.id,
                userId: invoice.userId,
                amount: invoice.amount,
                description: invoice.description,
                fileURL: invoice.fileURL,
                fileType: invoice.fileType,
                fileName: invoice.fileName,
                createdAt: invoice.createdAt,
                paidAt: Date(),
                paidBy: paidBy,
                paymentMethod: paymentMethod
            )
            
            try await FirebaseService.shared.updateInvoice(userId: userId, invoice: updatedInvoice)
            
            await MainActor.run {
                dismiss()
                onSave()
            }
        } catch {
            errorMessage = "Failed to mark invoice as paid: \(error.localizedDescription)"
            showingError = true
            isSaving = false
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

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

