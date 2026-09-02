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
    /// Which terminal this form belongs to. `nil` keeps the legacy
    /// single-terminal behaviour byte-for-byte (storage layer treats
    /// nil + 1 the same). For multi-terminal locations the host
    /// (multi-terminal close-out sheet) passes the explicit number.
    var terminalNumber: Int? = nil
    @Environment(\.dismiss) var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var rowValues: [String: String] = [:] // Track ending numbers by row ID
    @State private var validationMessage: String?
    @State private var showingValidationMessage = false
    @State private var showingCloseWarning = false
    @State private var closeWarningRows: [EmployeeHomeViewModel.ValidationResult.IncompleteRow] = []
    // Begin numbers were refreshed at close time (stale-data guard) —
    // employee reviews the changes and confirms to retry the close.
    @State private var showingBeginRefreshConfirm = false
    @State private var beginRefreshMessage = ""
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

    /// Counted cash enclosed for this shift — required before close so
    /// managers see actual bag cash (not only calculated shift-end cash).
    @State private var cashInHandValue: String = ""
    @FocusState private var isCashInHandFocused: Bool
    
    // Focus management for keyboard navigation - use @StateObject wrapper to prevent cycles
    @State private var focusedRowId: String? = nil
    @State private var shiftCloseScanTarget: LotteryShiftCloseScanTarget?
    @State private var showingExternalScanner = false
    
    // Performance optimization: Create row lookup dictionary once
    private var rowLookup: [String: LotteryFormTemplateRow] {
        Dictionary(uniqueKeysWithValues: template.rows.map { ($0.id, $0) })
    }
    
    private var scannableBinCount: Int {
        LotteryShiftCloseScanMatcher.scannableRows(from: template.rows).count
    }

    private var hasScannableBins: Bool {
        scannableBinCount > 0
    }

    private var isLotteryScanOnly: Bool {
        viewModel.location?.isLotteryScanOnly == true
    }

    private var showsScanChrome: Bool {
        hasScannableBins || isLotteryScanOnly
    }

    fileprivate static let endWarningSlotWidth: CGFloat = 20
    fileprivate static let endScanSlotWidth: CGFloat = 28

    private var lotteryFormTable: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 4
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    headerCell("Bin #", width: columnWidth)
                    headerCell("Value", width: columnWidth)
                    headerCell("Begin #", width: columnWidth)
                    endHeaderCell(width: columnWidth)
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

                dataRowsView(columnWidth: columnWidth)
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
        .frame(height: CGFloat(template.rows.count + 1) * 44)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                shiftCloseScanSection
                lotteryFormTable
                onlineAndCashFieldsSection
                cashInHandEntrySection
                lotteryPhotoSection
                closeLotteryButton
            }
            .padding(.horizontal)
            .padding(.vertical)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.cloudWhite)
        .onAppear {
            // Initialize row values from template (optimized batch operation)
            rowValues = Dictionary(uniqueKeysWithValues: template.rows.map { ($0.id, $0.endingNumber) })
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isCashInHandFocused = false
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            LotteryCameraPickerView(imageData: $imageData, capturedImage: $capturedImage)
        }
        .fullScreenCover(item: $shiftCloseScanTarget) { target in
            LotteryShiftCloseScannerSheet(
                target: target,
                rows: template.rows,
                reverseOrder: template.reverseOrder,
                rowValues: $rowValues,
                onPersistEnding: { rowId, ending, barcode in
                    try await viewModel.updateLotteryRowEndingFromScan(
                        rowId: rowId,
                        endingNumber: ending,
                        barcode: barcode,
                        terminalNumber: terminalNumber
                    )
                },
                onResolveUnrecognizedPack: { scenario, barcode, rowId, returnTicket, ending, creditSealedBeginAsFullBook in
                    try await viewModel.resolveShiftCloseUnrecognizedPack(
                        barcode: barcode,
                        scenario: scenario,
                        targetRowId: rowId,
                        returnTicket: returnTicket,
                        endingNumber: ending,
                        creditSealedBeginAsFullBook: creditSealedBeginAsFullBook,
                        terminalNumber: terminalNumber
                    )
                }
            )
        }
        .fullScreenCover(isPresented: $showingExternalScanner) {
            LotteryShiftCloseExternalScannerSheet(
                rows: template.rows,
                reverseOrder: template.reverseOrder,
                rowValues: $rowValues,
                onPersistEnding: { rowId, ending, barcode in
                    try await viewModel.updateLotteryRowEndingFromScan(
                        rowId: rowId,
                        endingNumber: ending,
                        barcode: barcode,
                        terminalNumber: terminalNumber
                    )
                },
                onResolveUnrecognizedPack: { scenario, barcode, rowId, returnTicket, ending, creditSealedBeginAsFullBook in
                    try await viewModel.resolveShiftCloseUnrecognizedPack(
                        barcode: barcode,
                        scenario: scenario,
                        targetRowId: rowId,
                        returnTicket: returnTicket,
                        endingNumber: ending,
                        creditSealedBeginAsFullBook: creditSealedBeginAsFullBook,
                        terminalNumber: terminalNumber
                    )
                }
            )
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
        .sheet(isPresented: $showingCloseWarning) {
            CloseIncompleteBinsSheet(
                rows: closeWarningRows,
                onGoBackToScan: {
                    showingCloseWarning = false
                },
                onContinue: { soldOutRowIds, returnedRowIds in
                    showingCloseWarning = false
                    Task {
                        do {
                            if !soldOutRowIds.isEmpty {
                                try await viewModel.markBinsSoldOutAtClose(
                                    rowIds: soldOutRowIds,
                                    terminalNumber: terminalNumber
                                )
                                await MainActor.run {
                                    for id in soldOutRowIds {
                                        rowValues[id] = "00"
                                    }
                                }
                            }
                            if !returnedRowIds.isEmpty {
                                try await viewModel.markBinsReturnedAtClose(
                                    rowIds: returnedRowIds,
                                    terminalNumber: terminalNumber
                                )
                                await MainActor.run {
                                    for id in returnedRowIds {
                                        rowValues[id] = ""
                                    }
                                }
                            }
                        } catch {
                            await MainActor.run {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                            return
                        }
                        await closeLotteryShift(skipValidation: true)
                    }
                }
            )
        }
        .alert("Begin numbers refreshed", isPresented: $showingBeginRefreshConfirm) {
            Button("Cancel", role: .cancel) {
                beginRefreshMessage = ""
            }
            Button("Confirm & Close") {
                Task {
                    await closeLotteryShift(skipValidation: true)
                }
            }
        } message: {
            Text(beginRefreshMessage)
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
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }

    private var shiftCloseScanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                focusedRowId = nil
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                shiftCloseScanTarget = .continuous(rows: template.rows)
            } label: {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan bins (camera)")
                            .font(.headline)
                        Text(hasScannableBins
                             ? "Walk the rack — camera stays open for each top ticket"
                             : "Manager must assign packs before you can scan")
                            .font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundColor(.white)
                .padding()
                .background(hasScannableBins ? Theme.cloudBlue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!hasScannableBins)

            Button {
                focusedRowId = nil
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                showingExternalScanner = true
            } label: {
                HStack {
                    Image(systemName: "barcode")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("External scanner")
                            .font(.headline)
                        Text(hasScannableBins
                             ? "Bluetooth / plug-in scanner — auto-fills End # and moves next"
                             : "Manager must assign packs before you can scan")
                            .font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundColor(.white)
                .padding()
                .background(hasScannableBins ? Color.orange : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!hasScannableBins)

            Text(isLotteryScanOnly
                 ? "Scan only is on — use Scan bins (camera) or External scanner so the session stays open for the whole rack. Typing End # is off. Row scan icons also open continuous mode."
                 : "Or tap the scan icon on a row to fill one End #. You can still type manually.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var onlineAndCashFieldsSection: some View {
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
        }
        .padding(.top, 20)
    }

    /// Photo and close live in the scroll view (not pinned above the keyboard).
    private var lotteryPhotoSection: some View {
        VStack(spacing: 12) {
            cameraButton
            if let capturedImage = capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .cornerRadius(12)
            }
        }
    }

    private func dataRowsView(columnWidth: CGFloat) -> some View {
        let allRowIds = template.rows.map { $0.id }
        return VStack(spacing: 0) {
            ForEach(Array(template.rows.enumerated()), id: \.element.id) { index, row in
                lotteryFormRowView(
                    index: index,
                    row: row,
                    allRowIds: allRowIds,
                    columnWidth: columnWidth
                )
            }
        }
    }
    
    private func lotteryFormRowView(
        index: Int,
        row: LotteryFormTemplateRow,
        allRowIds: [String],
        columnWidth: CGFloat
    ) -> some View {
        let canScanRow = !row.beginningNumber.isEmpty
            && !row.gameNumber.isEmpty
            && row.packStatus != .returned
            && row.packStatus != .empty

        return LotteryFormRowView(
            index: index,
            row: row,
            rowValue: rowValues[row.id] ?? row.endingNumber,
            columnWidth: columnWidth,
            rowLookup: rowLookup,
            allRowIds: allRowIds,
            focusedRowId: $focusedRowId,
            isLastRow: index == template.rows.count - 1,
            showsScanChrome: showsScanChrome,
            canScanEnding: canScanRow,
            allowsManualEntry: !isLotteryScanOnly,
            onScanEnding: canScanRow ? {
                focusedRowId = nil
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                // Scan-only locations can't type Ends — open continuous rack
                // walk so the camera stays open between bins (one-shot per-row
                // scan was closing after each ticket and felt broken).
                if isLotteryScanOnly {
                    shiftCloseScanTarget = .continuous(rows: template.rows)
                } else {
                    shiftCloseScanTarget = LotteryShiftCloseScanTarget(
                        id: row.id,
                        binNumber: index + 1,
                        row: row
                    )
                }
            } : nil,
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
        // Debounced save — surface failures so End doesn't look saved when Firestore rejected it.
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if rowValues[rowId] == newValue {
                do {
                    try await viewModel.updateLotteryRowEndingNumber(
                        rowId: rowId,
                        endingNumber: newValue,
                        terminalNumber: terminalNumber
                    )
                } catch {
                    await MainActor.run {
                        errorMessage = "Couldn't save End #: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
        }
    }

    private var cameraButton: some View {
        Button(action: {
            // Drop focus and dismiss the number pad before presenting the
            // camera. A `.sheet` with UIImagePickerController often clipped
            // the shutter / capture UI; `fullScreenCover` + a short delay
            // after resignFirstResponder keeps the native controls visible.
            focusedRowId = nil
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showingCamera = true
            }
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
    }

    private var cashInHandEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LotterySummaryDisplayName.actualEnclosedCash)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            Text("Please enter how much cash you are dropping in the safe.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("$")
                    .font(.system(size: 16, weight: .semibold))
                TextField("0.00", text: $cashInHandValue)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 16, weight: .semibold))
                    .focused($isCashInHandFocused)
                    .onChange(of: cashInHandValue) { _, newValue in
                        cashInHandValue = CashEnclosedInput.sanitize(newValue)
                    }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        canCloseShift ? Color.gray.opacity(0.3) : Color.red.opacity(0.5),
                        lineWidth: 1
                    )
            )

            if cashInHandValue.isEmpty {
                Text("Required before you can close this shift")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 8)
    }

    private var canCloseShift: Bool {
        capturedImage != nil && parsedCashInHand != nil
    }

    private var parsedCashInHand: Double? {
        CashEnclosedInput.parse(cashInHandValue)
    }

    private var closeLotteryButton: some View {
        Button(action: {
            Task {
                await checkAndShowCloseWarning()
            }
        }) {
            HStack {
                if !canCloseShift {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.headline)
                }
                Text("Close Lottery Shift")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canCloseShift ? Color.red : Color.gray)
            .cornerRadius(12)
        }
        .disabled(isSaving || !canCloseShift)
    }
    
    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .frame(width: width, height: 44)
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

    private func endHeaderCell(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if showsScanChrome {
                Color.clear.frame(width: Self.endWarningSlotWidth)
            }
            Text("End #")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
            if showsScanChrome {
                Color.clear.frame(width: Self.endScanSlotWidth)
            }
        }
        .frame(width: width, height: 44)
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
        
        // Validate the form against the terminal we're closing
        let validation = await viewModel.validateLotteryForm(terminalNumber: terminalNumber)
        
        if validation.hasIncompleteRows {
            await MainActor.run {
                closeWarningRows = validation.incompleteRows
                showingCloseWarning = true
            }
        } else {
            // No incomplete rows, proceed directly
            await closeLotteryShift(skipValidation: true)
        }
    }
    
    // Close lottery shift function
    private func closeLotteryShift(skipValidation: Bool = false) async {
        // A close is already running (double tap / repeated alert
        // confirmation) — never start a second one.
        guard !isSaving else { return }

        // Double-check that image has been taken
        if capturedImage == nil && imageData == nil {
            await MainActor.run {
                errorMessage = "Please take a photo before closing the lottery shift."
                showingError = true
                isSaving = false
            }
            return
        }

        guard let cashInHand = parsedCashInHand else {
            await MainActor.run {
                errorMessage = "Please enter the cash in hand amount you enclosed for this shift."
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
            
            // Close lottery shift with calculations and report creation.
            // `terminalNumber == nil` keeps every existing single-terminal
            // call site behaving exactly as it did before multi-terminal.
            // Prefer JPEG from imageData; if only the UIImage preview
            // exists, encode it so the receipt still uploads.
            let photoData = imageData ?? capturedImage?.jpegData(compressionQuality: 0.8)
            let completedForm = try await viewModel.closeLotteryShift(
                formData: formData,
                onlineTotals: onlineTotals.filter { !$0.isEmpty },
                onlineCashes: onlineCashes.filter { !$0.isEmpty },
                instantCashes: instantCashes.filter { !$0.isEmpty },
                imageData: photoData,
                registerCash: registerCash,
                cashInHand: cashInHand,
                skipValidation: skipValidation,
                terminalNumber: terminalNumber
            )
            
            // Show summary immediately without waiting for template reload
            await MainActor.run {
                isSaving = false
                completedLotteryForm = completedForm
                showingShiftSummary = true
            }
            
            // Reload template in the background (non-blocking) so the
            // user sees their new beginning numbers if they re-open
            // the form. For multi-terminal locations we re-read the
            // specific terminal we just closed; for single-terminal
            // we just refresh `lotteryTemplate` like before.
            Task.detached(priority: .background) {
                await viewModel.loadLotteryTemplate()

                await MainActor.run {
                    let refreshedTemplate: LotteryFormTemplate? = {
                        if let terminalNumber = terminalNumber {
                            return viewModel.lotteryTemplates[terminalNumber]
                        }
                        return viewModel.lotteryTemplate
                    }()
                    if let updatedTemplate = refreshedTemplate {
                        for row in updatedTemplate.rows {
                            rowValues[row.id] = row.endingNumber
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                isSaving = false
                if (error as NSError).code == 101 {
                    // Stale Begin numbers were auto-corrected on the
                    // server — show what changed and let the employee
                    // confirm; the retry re-verifies and passes.
                    beginRefreshMessage = error.localizedDescription
                    showingBeginRefreshConfirm = true
                } else {
                    errorMessage = "Failed to close lottery shift: \(error.localizedDescription)"
                    showingError = true
                }
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
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = true
        // When this VC is embedded in SwiftUI, default modal style can
        // still interact oddly; fullScreen is the safe default for camera.
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        uiViewController.showsCameraControls = true
    }
    
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
    var showsScanChrome: Bool = false
    var canScanEnding: Bool = false
    var allowsManualEntry: Bool = true
    var onScanEnding: (() -> Void)?
    let onValueChanged: (String) -> Void
    
    @State private var localValue: String
    
    init(
        index: Int,
        row: LotteryFormTemplateRow,
        rowValue: String,
        columnWidth: CGFloat,
        rowLookup: [String: LotteryFormTemplateRow],
        allRowIds: [String],
        focusedRowId: Binding<String?>,
        isLastRow: Bool,
        showsScanChrome: Bool = false,
        canScanEnding: Bool = false,
        allowsManualEntry: Bool = true,
        onScanEnding: (() -> Void)? = nil,
        onValueChanged: @escaping (String) -> Void
    ) {
        self.index = index
        self.row = row
        self.rowValue = rowValue
        self.columnWidth = columnWidth
        self.rowLookup = rowLookup
        self.allRowIds = allRowIds
        self._focusedRowId = focusedRowId
        self.isLastRow = isLastRow
        self.showsScanChrome = showsScanChrome
        self.canScanEnding = canScanEnding
        self.allowsManualEntry = allowsManualEntry
        self.onScanEnding = onScanEnding
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
            
            // End # — fixed slots so warning / value / scan stay aligned with header
            HStack(spacing: 0) {
                if showsScanChrome {
                    Group {
                        if isBookCycled(beginning: row.beginningNumber, ending: localValue) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.yellow)
                        }
                    }
                    .frame(width: EmployeeLotteryFormView.endWarningSlotWidth)
                }

                NumberPadTextField(
                    text: $localValue,
                    rowId: row.id,
                    focusedRowId: $focusedRowId,
                    isLastRow: isLastRow,
                    isEditable: allowsManualEntry,
                    onNext: {
                        moveToNextRow()
                    },
                    onDone: {
                        focusedRowId = nil
                    }
                )
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(allowsManualEntry ? .black : .secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .opacity(allowsManualEntry ? 1 : 0.85)

                if showsScanChrome {
                    Group {
                        if canScanEnding, let onScanEnding {
                            Button(action: onScanEnding) {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.cloudBlue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: EmployeeLotteryFormView.endScanSlotWidth, height: 44)
                }
            }
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
    var isEditable: Bool = true
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
        context.coordinator.parent = self
        uiView.isEnabled = isEditable
        uiView.isUserInteractionEnabled = isEditable

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
        var parent: NumberPadTextField
        weak var textField: UITextField?
        
        init(_ parent: NumberPadTextField) {
            self.parent = parent
        }

        func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
            parent.isEditable
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

/// Shown when the employee tries to close with bins missing End # (or other
/// required fields). Every resolvable bin must be marked **Sold out** or
/// **Returned** — no silent skip. Cancel returns them to scan/fix entry.
struct CloseIncompleteBinsSheet: View {
    enum Disposition: Equatable {
        case soldOut
        case returned
    }

    let rows: [EmployeeHomeViewModel.ValidationResult.IncompleteRow]
    let onGoBackToScan: () -> Void
    /// soldOutRowIds, returnedRowIds
    let onContinue: ([String], [String]) -> Void

    @State private var dispositions: [String: Disposition] = [:]
    @State private var showingLargeSoldOutConfirm = false

    private var unresolvableRows: [EmployeeHomeViewModel.ValidationResult.IncompleteRow] {
        rows.filter { !$0.canResolveAtClose }
    }

    private var resolvableRows: [EmployeeHomeViewModel.ValidationResult.IncompleteRow] {
        rows.filter { $0.canResolveAtClose }
    }

    private var allResolvableChosen: Bool {
        resolvableRows.allSatisfy { dispositions[$0.rowId] != nil }
    }

    private var canClose: Bool {
        unresolvableRows.isEmpty && allResolvableChosen
    }

    private var soldOutTotalDollars: Int {
        rows.reduce(0) { partial, row in
            guard dispositions[row.rowId] == .soldOut else { return partial }
            return partial + row.soldOutDollars
        }
    }

    private var soldOutTotalTickets: Int {
        rows.reduce(0) { partial, row in
            guard dispositions[row.rowId] == .soldOut else { return partial }
            return partial + row.soldOutTickets
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("These bins are missing End #. Choose Sold out or Returned for each one, or go back and scan. You can’t skip a bin without a reason.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !unresolvableRows.isEmpty {
                    Section {
                        ForEach(unresolvableRows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                rowTitle(row)
                                Text("Missing \(row.missingFields.joined(separator: ", ")). Go back and scan or fix this bin on the form — it can’t be resolved here.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    } header: {
                        Text("Need scan / fix")
                    }
                }

                Section {
                    ForEach(resolvableRows) { row in
                        VStack(alignment: .leading, spacing: 10) {
                            rowTitle(row)
                            Text("Missing \(row.missingFields.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if row.canMarkSoldOut {
                                dispositionButton(
                                    title: "Sold out",
                                    subtitle: "Begin \(displayTicket(row.beginningNumber)) → 00 = \(row.soldOutTickets) tickets · $\(row.soldOutDollars). Next Begin \(displayTicket(row.nextBeginAfterSoldOut)).",
                                    selected: dispositions[row.rowId] == .soldOut,
                                    tint: .orange
                                ) {
                                    dispositions[row.rowId] = .soldOut
                                }
                            }

                            if row.canMarkReturned {
                                dispositionButton(
                                    title: "Returned",
                                    subtitle: "$0 this shift — pack cleared from rack",
                                    selected: dispositions[row.rowId] == .returned,
                                    tint: .blue
                                ) {
                                    dispositions[row.rowId] = .returned
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Incomplete bins")
                }

                if soldOutTotalDollars > 0 || soldOutTotalTickets > 0 {
                    Section {
                        Text("From sold-out choices: \(soldOutTotalTickets) tickets · $\(soldOutTotalDollars)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Bins not scanned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Go back to scan", action: onGoBackToScan)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close shift") {
                        if soldOutTotalDollars >= 50 {
                            showingLargeSoldOutConfirm = true
                        } else {
                            submit()
                        }
                    }
                    .disabled(!canClose)
                }
            }
            .alert("Confirm sold-out credit", isPresented: $showingLargeSoldOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Confirm & close") { submit() }
            } message: {
                Text("You’re crediting \(soldOutTotalTickets) tickets · $\(soldOutTotalDollars) for finished packs that weren’t scanned. Continue only if those books really sold out.")
            }
        }
    }

    private func submit() {
        let soldOut = rows.compactMap { dispositions[$0.rowId] == .soldOut ? $0.rowId : nil }
        let returned = rows.compactMap { dispositions[$0.rowId] == .returned ? $0.rowId : nil }
        onContinue(soldOut, returned)
    }

    private func displayTicket(_ value: String) -> String {
        value == "0" ? "00" : value
    }

    @ViewBuilder
    private func rowTitle(_ row: EmployeeHomeViewModel.ValidationResult.IncompleteRow) -> some View {
        HStack(spacing: 6) {
            Text("Bin #\(row.binNumber)")
                .font(.headline)
            if row.gameNumber != "N/A" {
                Text("Game \(row.gameNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func dispositionButton(
        title: String,
        subtitle: String,
        selected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? tint : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? tint.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? tint.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

