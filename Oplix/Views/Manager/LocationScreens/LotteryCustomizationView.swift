//
//  LotteryCustomizationView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryCustomizationView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var template: LotteryFormTemplate
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var selectedRows: Set<String> = []
    
    init(viewModel: LocationDetailViewModel) {
        self.viewModel = viewModel
        _template = State(initialValue: viewModel.lotteryFormTemplate ?? LotteryFormTemplate(locationId: viewModel.locationId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Add/Delete Buttons at Top
                    HStack(spacing: 12) {
                        Button(action: {
                            addRow()
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Row")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.cloudBlue)
                            .cornerRadius(8)
                        }
                        
                        Button(action: {
                            deleteSelectedRows()
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Delete Selected")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selectedRows.isEmpty ? Color.gray : Color.red)
                            .cornerRadius(8)
                        }
                        .disabled(selectedRows.isEmpty)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Theme.cloudWhite)
                    
                    Divider()
                    
                    // Lottery Form Section
                    VStack(spacing: 12) {
                        HStack {
                            Text("Lottery Form")
                                .font(.headline)
                                .foregroundColor(.black)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        if template.rows.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No rows yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Tap 'Add Row' to create your first row")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ScrollView {
                                VStack(spacing: 0) {
                                    // Data rows
                                    ForEach(template.rows) { row in
                                        HStack(spacing: 0) {
                                            // Selection checkbox
                                            Button(action: {
                                                if selectedRows.contains(row.id) {
                                                    selectedRows.remove(row.id)
                                                } else {
                                                    selectedRows.insert(row.id)
                                                }
                                            }) {
                                                Image(systemName: selectedRows.contains(row.id) ? "checkmark.square.fill" : "square")
                                                    .foregroundColor(selectedRows.contains(row.id) ? Theme.cloudBlue : .gray)
                                                    .frame(width: 44)
                                            }
                                            
                                            ForEach(0..<8, id: \.self) { colIndex in
                                                TextField("", text: Binding(
                                                    get: {
                                                        colIndex < row.values.count ? row.values[colIndex] : ""
                                                    },
                                                    set: { newValue in
                                                        if let index = template.rows.firstIndex(where: { $0.id == row.id }) {
                                                            if colIndex < template.rows[index].values.count {
                                                                template.rows[index].values[colIndex] = newValue
                                                            } else {
                                                                while template.rows[index].values.count <= colIndex {
                                                                    template.rows[index].values.append("")
                                                                }
                                                                template.rows[index].values[colIndex] = newValue
                                                            }
                                                        }
                                                    }
                                                ))
                                                .textFieldStyle(.plain)
                                                .font(.subheadline)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .padding(.horizontal, 4)
                                                .background(Color.white)
                                                .overlay(
                                                    Rectangle()
                                                        .frame(width: 1)
                                                        .foregroundColor(Color.gray.opacity(0.3)),
                                                    alignment: .trailing
                                                )
                                            }
                                        }
                                        .overlay(
                                            Rectangle()
                                                .frame(height: 1)
                                                .foregroundColor(Color.gray.opacity(0.3)),
                                            alignment: .bottom
                                        )
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.cloudWhite)
                }
            }
            .navigationTitle("Lottery Form Customization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Save") {
                        Task {
                            await saveTemplate()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addRow() {
        let newRow = LotteryFormTemplateRow(values: Array(repeating: "", count: 8))
        template.rows.append(newRow)
    }
    
    private func deleteRow(_ row: LotteryFormTemplateRow) {
        template.rows.removeAll { $0.id == row.id }
        selectedRows.remove(row.id)
    }
    
    private func deleteSelectedRows() {
        template.rows.removeAll { selectedRows.contains($0.id) }
        selectedRows.removeAll()
    }
    
    private func saveTemplate() async {
        isSaving = true
        errorMessage = ""
        
        // Ensure column headers array has exactly 8 items
        while template.columnHeaders.count < 8 {
            template.columnHeaders.append("")
        }
        template.columnHeaders = Array(template.columnHeaders.prefix(8))
        
        // Ensure all rows have exactly 8 values
        for index in template.rows.indices {
            while template.rows[index].values.count < 8 {
                template.rows[index].values.append("")
            }
            template.rows[index].values = Array(template.rows[index].values.prefix(8))
        }
        
        await viewModel.saveLotteryFormTemplate(template)
        
        if viewModel.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = viewModel.errorMessage ?? "Failed to save template"
            showingError = true
        }
        
        isSaving = false
    }
}

#Preview {
    LotteryCustomizationView(viewModel: LocationDetailViewModel(userId: "test", locationId: "test"))
}

