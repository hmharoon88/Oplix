//
//  EmployeeLotteryFormView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeLotteryFormView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    let template: LotteryFormTemplate
    @Environment(\.dismiss) var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var rowValues: [String: String] = [:] // Track ending numbers by row ID
    @State private var validationMessage: String?
    @State private var showingValidationMessage = false
    @State private var showingCloseWarning = false
    @State private var closeWarningMessage = ""
    @State private var showingShiftSummary = false
    @State private var completedLotteryForm: LotteryForm?
    
    // Additional fields
    @State private var onlineTotals: [String] = [""]
    @State private var onlineCashes: [String] = [""]
    @State private var instantCashes: [String] = [""]
    
    // Camera
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var imageData: Data?
    
    // Focus management for keyboard navigation - use @StateObject wrapper to prevent cycles
    @State private var focusedRowId: String? = nil
    
    // Performance optimization: Create row lookup dictionary once
    private var rowLookup: [String: LotteryFormTemplateRow] {
        Dictionary(uniqueKeysWithValues: template.rows.map { ($0.id, $0) })
    }
    
    private var columnWidth: CGFloat {
        // Calculate width to fit 4 columns on screen
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 16 // Side padding
        let availableWidth = screenWidth - padding * 2
        return availableWidth / 4
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                lotteryFormTable
                additionalFieldsSection
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .background(Theme.cloudWhite)
        .onAppear {
            // Initialize row values from template (optimized batch operation)
            rowValues = Dictionary(uniqueKeysWithValues: template.rows.map { ($0.id, $0.endingNumber) })
        }
        .sheet(isPresented: $showingCamera) {
            LotteryCameraPickerView(imageData: $imageData, capturedImage: $capturedImage)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Incomplete Rows Detected", isPresented: $showingCloseWarning) {
            Button("Cancel", role: .cancel) {
                closeWarningMessage = ""
            }
            Button("Close Anyway", role: .destructive) {
                Task {
                    await closeLotteryShift(skipValidation: true)
                }
            }
        } message: {
            Text(closeWarningMessage)
        }
        .fullScreenCover(isPresented: $showingShiftSummary) {
            if let form = completedLotteryForm, let summary = form.shiftSummary {
                LotteryShiftSummarySheet(
                    summary: summary,
                    form: form,
                    template: template,
                    onDismiss: {
                        showingShiftSummary = false
                        dismiss()
                    },
                    viewModel: viewModel
                )
            }
        }
    }
    
    private var lotteryFormTable: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                headerCell("Bin #")
                headerCell("Value")
                headerCell("Begin #")
                headerCell("End #")
            }
            .background(Theme.cloudBlue.opacity(0.2))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .bottom
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .top
            )
            
            // Data Rows
            dataRowsView
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
    }
    
    private var dataRowsView: some View {
        let allRowIds = template.rows.map { $0.id }
        return LazyVStack(spacing: 0) {
            ForEach(Array(template.rows.enumerated()), id: \.element.id) { index, row in
                lotteryFormRowView(
                    index: index,
                    row: row,
                    allRowIds: allRowIds
                )
            }
        }
    }
    
    private func lotteryFormRowView(index: Int, row: LotteryFormTemplateRow, allRowIds: [String]) -> some View {
        LotteryFormRowView(
            index: index,
            row: row,
            rowValue: rowValues[row.id] ?? row.endingNumber,
            columnWidth: columnWidth,
            rowLookup: rowLookup,
            allRowIds: allRowIds,
            focusedRowId: $focusedRowId,
            isLastRow: index == template.rows.count - 1,
            onValueChanged: { newValue in
                handleRowValueChanged(rowId: row.id, newValue: newValue)
            }
        )
        .background(index % 2 == 0 ? Theme.cloudWhite : Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.5)),
            alignment: .bottom
        )
    }
    
    private func handleRowValueChanged(rowId: String, newValue: String) {
        rowValues[rowId] = newValue
        // Debounced save
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if rowValues[rowId] == newValue {
                try? await viewModel.updateLotteryRowEndingNumber(rowId: rowId, endingNumber: newValue)
            }
        }
    }
    
    private var additionalFieldsSection: some View {
        VStack(spacing: 16) {
            multipleFieldSection(
                title: "Online Total",
                values: $onlineTotals,
                placeholder: "Enter amount"
            )
            
            multipleFieldSection(
                title: "Online Cashes",
                values: $onlineCashes,
                placeholder: "Enter amount"
            )
            
            multipleFieldSection(
                title: "Instant Cashes",
                values: $instantCashes,
                placeholder: "Enter amount"
            )
            
            cameraButton
            
            if let capturedImage = capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .padding(.horizontal)
            }
            
            closeLotteryButton
        }
        .padding(.top, 20)
    }
    
    private var cameraButton: some View {
        Button(action: {
            showingCamera = true
        }) {
            HStack {
                Image(systemName: capturedImage != nil ? "checkmark.circle.fill" : "camera.fill")
                    .font(.title2)
                Text(capturedImage != nil ? "Photo Taken" : "Take Photo")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(capturedImage != nil ? Color.green : Theme.cloudBlue)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
    
    private var closeLotteryButton: some View {
        Button(action: {
            Task {
                await checkAndShowCloseWarning()
            }
        }) {
            HStack {
                if capturedImage == nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.headline)
                }
                Text("Close Lottery Shift")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(capturedImage != nil ? Color.red : Color.gray)
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .disabled(isSaving || capturedImage == nil)
    }
    
    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .frame(width: columnWidth, height: 44)
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
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
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
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
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
    
    // Format value with dollar sign
    private func formatValue(_ value: String) -> String {
        if value.isEmpty {
            return ""
        }
        // Remove $ if present, then add it back
        let cleanValue = value.replacingOccurrences(of: "$", with: "")
        return cleanValue.isEmpty ? "" : "$\(cleanValue)"
    }
    
    // Removed editableCell - now handled by LotteryFormRowView for better performance
    
    // Helper function to create multiple field sections
    private func multipleFieldSection(title: String, values: Binding<[String]>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal)
            }
            
            ForEach(Array(values.wrappedValue.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        if values.wrappedValue[index].isEmpty {
                            Text(placeholder)
                                .foregroundColor(Color.gray.opacity(0.6))
                                .padding(.horizontal, 12)
                        }
                        TextField("", text: Binding(
                            get: { values.wrappedValue[index] },
                            set: { values.wrappedValue[index] = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .keyboardType(.decimalPad)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                    }
                    .padding(.vertical, 10)
                    .background(Theme.cloudWhite)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    
                    if index == values.wrappedValue.count - 1 {
                        Button(action: {
                            values.wrappedValue.append("")
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Theme.cloudBlue)
                        }
                    }
                    
                    if values.wrappedValue.count > 1 {
                        Button(action: {
                            values.wrappedValue.remove(at: index)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // Check for incomplete rows and show warning before closing
    private func checkAndShowCloseWarning() async {
        // First check if image has been taken
        if capturedImage == nil && imageData == nil {
            await MainActor.run {
                errorMessage = "Please take a photo before closing the lottery shift."
                showingError = true
            }
            return
        }
        
        // Reload template to get latest data
        await viewModel.loadLotteryTemplate()
        
        // Validate the form
        let validation = await viewModel.validateLotteryForm()
        
        if validation.hasIncompleteRows {
            // Build warning message
            var message = "Some rows have missing fields:\n\n"
            for incompleteRow in validation.incompleteRows {
                message += "Bin #\(incompleteRow.binNumber)"
                if !incompleteRow.gameNumber.isEmpty && incompleteRow.gameNumber != "N/A" {
                    message += " (Game #\(incompleteRow.gameNumber))"
                }
                message += ": Missing \(incompleteRow.missingFields.joined(separator: ", "))\n"
            }
            message += "\nThese rows will not be included in calculations. Do you want to proceed anyway?"
            
            await MainActor.run {
                closeWarningMessage = message
                showingCloseWarning = true
            }
        } else {
            // No incomplete rows, proceed directly
            await closeLotteryShift(skipValidation: true)
        }
    }
    
    // Close lottery shift function
    private func closeLotteryShift(skipValidation: Bool = false) async {
        // Double-check that image has been taken
        if capturedImage == nil && imageData == nil {
            await MainActor.run {
                errorMessage = "Please take a photo before closing the lottery shift."
                showingError = true
                isSaving = false
            }
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        // Collect all form data
        var formData: [String: String] = [:]
        
        // Add row values
        for (rowId, value) in rowValues {
            formData["row_\(rowId)"] = value
        }
        
        // Get register cash from template (lottery register amount)
        let registerCash = template.lotteryRegisterAmount.isEmpty ? nil : template.lotteryRegisterAmount
        
        do {
            // Verify employee is still clocked in before closing
            guard let currentShift = viewModel.currentShift, currentShift.isActive else {
                await MainActor.run {
                    errorMessage = "You must be clocked in to submit a lottery form. Please clock in first."
                    showingError = true
                    isSaving = false
                }
                return
            }
            
            // Close lottery shift with calculations and report creation
            let completedForm = try await viewModel.closeLotteryShift(
                formData: formData,
                onlineTotals: onlineTotals.filter { !$0.isEmpty },
                onlineCashes: onlineCashes.filter { !$0.isEmpty },
                instantCashes: instantCashes.filter { !$0.isEmpty },
                imageData: imageData,
                registerCash: registerCash,
                skipValidation: skipValidation
            )
            
            // Show summary immediately without waiting for template reload
            await MainActor.run {
                isSaving = false
                completedLotteryForm = completedForm
                showingShiftSummary = true
            }
            
            // Reload template in the background (non-blocking)
            Task.detached(priority: .background) {
                await viewModel.loadLotteryTemplate()
                
                // Update local row values to reflect new beginning numbers (which should now be empty)
                await MainActor.run {
                    if let updatedTemplate = viewModel.lotteryTemplate {
                        for row in updatedTemplate.rows {
                            rowValues[row.id] = row.endingNumber // This will be empty after the shift closes
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to close lottery shift: \(error.localizedDescription)"
                showingError = true
                isSaving = false
            }
        }
    }
}

// Camera Picker View for Employee Lottery Form
struct LotteryCameraPickerView: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: LotteryCameraPickerView
        
        init(_ parent: LotteryCameraPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                parent.imageData = imageData
                parent.capturedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Optimized Row View for Performance
struct LotteryFormRowView: View {
    let index: Int
    let row: LotteryFormTemplateRow
    let rowValue: String
    let columnWidth: CGFloat
    let rowLookup: [String: LotteryFormTemplateRow]
    let allRowIds: [String]
    @Binding var focusedRowId: String?
    let isLastRow: Bool
    let onValueChanged: (String) -> Void
    
    @State private var localValue: String
    
    init(index: Int, row: LotteryFormTemplateRow, rowValue: String, columnWidth: CGFloat, rowLookup: [String: LotteryFormTemplateRow], allRowIds: [String], focusedRowId: Binding<String?>, isLastRow: Bool, onValueChanged: @escaping (String) -> Void) {
        self.index = index
        self.row = row
        self.rowValue = rowValue
        self.columnWidth = columnWidth
        self.rowLookup = rowLookup
        self.allRowIds = allRowIds
        self._focusedRowId = focusedRowId
        self.isLastRow = isLastRow
        self.onValueChanged = onValueChanged
        _localValue = State(initialValue: rowValue)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Bin# - read-only serial number
            Text(String(index + 1))
                .font(.system(size: 11))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: columnWidth, height: 44)
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
            
            // Value - read-only (formatted with $)
            Text(formatValue(row.value))
                .font(.system(size: 11))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: columnWidth, height: 44)
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
            
            // Begin # - read-only
            Text(row.beginningNumber.isEmpty ? "—" : row.beginningNumber)
                .font(.system(size: 11))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: columnWidth, height: 44)
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
            
            // End # - editable
            ZStack {
                NumberPadTextField(
                    text: $localValue,
                    rowId: row.id,
                    focusedRowId: $focusedRowId,
                    isLastRow: isLastRow,
                    onNext: {
                        moveToNextRow()
                    },
                    onDone: {
                        focusedRowId = nil
                    }
                )
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black)
                .frame(width: columnWidth, height: 44)
                
                // Yellow warning indicator for book cycled
                if isBookCycled(beginning: row.beginningNumber, ending: localValue) {
                    HStack {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                            .padding(.trailing, 4)
                    }
                }
            }
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
            .onChange(of: localValue) { _, newValue in
                let filtered = filterInput(newValue)
                if filtered != newValue {
                    localValue = filtered
                } else {
                    validateAndUpdate(filtered)
                }
            }
            .onChange(of: rowValue) { _, newValue in
                if newValue != localValue {
                    localValue = newValue
                }
            }
        }
    }
    
    private func formatValue(_ value: String) -> String {
        if value.isEmpty {
            return ""
        }
        let cleanValue = value.replacingOccurrences(of: "$", with: "")
        return cleanValue.isEmpty ? "" : "$\(cleanValue)"
    }
    
    private func filterInput(_ input: String) -> String {
        var filtered = ""
        var hasDecimal = false
        for char in input {
            if char.isNumber {
                filtered.append(char)
            } else if char == "." && !hasDecimal {
                filtered.append(char)
                hasDecimal = true
            }
        }
        
        // Normalize "0" to "00" for ticket number fields
        if filtered == "0" {
            filtered = "00"
        }
        
        return filtered
    }
    
    private func validateAndUpdate(_ value: String) {
        // Validate ticket number range
        if !value.isEmpty && value != "00" {
            if let ticketsInt = Int(row.tickets), ticketsInt > 0 {
                let maxTicketNumber = ticketsInt - 1
                if let enteredNum = Int(value), enteredNum > maxTicketNumber {
                    // Revert to previous value
                    localValue = rowValue
                    return
                }
            }
        }
        
        // Update value
        onValueChanged(value)
    }
    
    /// Check if the ending number indicates a book cycled (ending < beginning)
    /// A book cycled means the ending number is significantly lower than the beginning number,
    /// indicating a book was completed and a new one started.
    private func isBookCycled(beginning: String, ending: String) -> Bool {
        // Both values must be non-empty and valid numbers
        guard !beginning.isEmpty, !ending.isEmpty,
              let beginningNum = Int(beginning),
              let endingNum = Int(ending) else {
            return false
        }
        
        // Book cycled if ending number is less than beginning number
        // This indicates a book was completed and a new one started
        return endingNum < beginningNum
    }
    
    private func moveToNextRow() {
        // Find the next row ID and set focusedRowId to move focus vertically
        if let currentIndex = allRowIds.firstIndex(of: row.id),
           currentIndex < allRowIds.count - 1 {
            let nextRowId = allRowIds[currentIndex + 1]
            // Use async to break potential cycles
            DispatchQueue.main.async {
                self.focusedRowId = nextRowId
            }
        } else {
            // If this is the last row, dismiss keyboard
            DispatchQueue.main.async {
                self.focusedRowId = nil
            }
        }
    }
}

// MARK: - Number Pad TextField
struct NumberPadTextField: UIViewRepresentable {
    @Binding var text: String
    let rowId: String
    @Binding var focusedRowId: String?
    let isLastRow: Bool
    let onNext: () -> Void
    let onDone: () -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .numberPad
        textField.textAlignment = .center
        textField.font = .systemFont(ofSize: 16, weight: .bold)
        textField.textColor = .black // Explicitly set text color to black
        textField.delegate = context.coordinator
        
        // No toolbar - removed as requested
        
        // Store coordinator reference
        context.coordinator.textField = textField
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Always ensure text color is black
        if uiView.textColor != .black {
            uiView.textColor = .black
        }
        
        // Only update text if it's different to avoid unnecessary updates
        let currentText = uiView.text ?? ""
        if currentText != text {
            uiView.text = text
        }
        
        // No toolbar updates needed - toolbar removed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: NumberPadTextField
        weak var textField: UITextField?
        
        init(_ parent: NumberPadTextField) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            // Only update if text actually changed
            let newText = textField.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
        }
    }
}

