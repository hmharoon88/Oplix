//
//  AddInvoiceView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AddInvoiceView: View {
    let userId: String
    let locationId: String?
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var amount: String = ""
    @State private var description: String = ""
    @State private var selectedImage: UIImage?
    @State private var fileData: Data?
    @State private var selectedFile: URL?
    @State private var fileName: String = ""
    @State private var fileType: String = ""
    @State private var showingImagePicker = false
    @State private var showingImageSourceSelection = false
    @State private var showingFilePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .camera
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    invoiceDetailsSection
                    invoiceFileSection
                    saveButtonSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Invoice")
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
            .confirmationDialog("Select Image Source", isPresented: $showingImageSourceSelection) {
                Button("Camera") {
                    imageSourceType = .camera
                    showingImagePicker = true
                }
                Button("Photo Library") {
                    imageSourceType = .photoLibrary
                    showingImagePicker = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePickerView(
                    sourceType: imageSourceType,
                    selectedImage: $selectedImage,
                    imageData: $fileData
                )
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result: result)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private var invoiceDetailsSection: some View {
        Section("Invoice Details") {
            TextField("Amount", text: $amount)
                .keyboardType(.decimalPad)
            
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(3...6)
        }
    }
    
    @ViewBuilder
    private var invoiceFileSection: some View {
        Section("Invoice File") {
            if selectedImage != nil {
                imageSelectedView
            } else if !fileName.isEmpty {
                fileSelectedView
            } else {
                noFileSelectedView
            }
        }
    }
    
    private var imageSelectedView: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(8)
            }
            
            Button("Change File") {
                showingImageSourceSelection = true
            }
            
            Button("Remove File", role: .destructive) {
                selectedImage = nil
                fileData = nil
                selectedFile = nil
                fileName = ""
                fileType = ""
            }
        }
    }
    
    private var fileSelectedView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: iconForFileType(fileType))
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(fileName)
                        .font(.headline)
                    Text(fileType.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Button("Change File") {
                showingFilePicker = true
            }
            
            Button("Remove File", role: .destructive) {
                selectedFile = nil
                fileData = nil
                fileName = ""
                fileType = ""
            }
        }
    }
    
    private var noFileSelectedView: some View {
        VStack(spacing: 12) {
            Button(action: {
                showingImageSourceSelection = true
            }) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Take Photo or Choose from Library")
                }
            }
            
            Button(action: {
                showingFilePicker = true
            }) {
                HStack {
                    Image(systemName: "folder.fill")
                    Text("Choose PDF or Excel File")
                }
            }
        }
    }
    
    private var saveButtonSection: some View {
        Section {
            Button(action: {
                Task {
                    await saveInvoice()
                }
            }) {
                if isSaving {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Text("Save Invoice")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(amount.isEmpty || description.isEmpty || isSaving)
        }
    }
    
    private func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedFile = url
                fileName = url.lastPathComponent
                fileType = (url.pathExtension as NSString).lowercased
                
                // Access security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "Failed to access file. Please try again."
                    showingError = true
                    return
                }
                
                defer {
                    url.stopAccessingSecurityScopedResource()
                }
                
                // Read file data
                do {
                    let data = try Data(contentsOf: url)
                    fileData = data
                    selectedImage = nil // Clear image if file is selected
                } catch {
                    errorMessage = "Failed to read file: \(error.localizedDescription)"
                    showingError = true
                }
            }
        case .failure(let error):
            errorMessage = "Failed to select file: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func iconForFileType(_ fileType: String) -> String {
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
    
    private func saveInvoice() async {
        guard let amountValue = Double(amount) else {
            errorMessage = "Please enter a valid amount"
            showingError = true
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        do {
            var fileURL: String? = nil
            var finalFileType: String? = nil
            var finalFileName: String? = nil
            
            // Upload file if provided
            if let fileData = fileData {
                let invoiceId = UUID().uuidString
                
                // Determine file type
                if selectedImage != nil {
                    // It's an image
                    finalFileType = "jpg"
                    finalFileName = "invoice_image.jpg"
                } else {
                    // It's a document (PDF, Excel, etc.)
                    finalFileType = fileType.isEmpty ? "pdf" : fileType
                    finalFileName = fileName.isEmpty ? "invoice_file.\(finalFileType!)" : fileName
                }
                
                fileURL = try await FirebaseService.shared.uploadInvoiceFile(
                    fileData: fileData,
                    invoiceId: invoiceId,
                    userId: userId,
                    fileType: finalFileType!,
                    fileName: finalFileName!
                )
            }
            
            // Create invoice with locationId
            let invoice = Invoice(
                userId: userId,
                locationId: locationId,
                amount: amountValue,
                description: description,
                fileURL: fileURL,
                fileType: finalFileType,
                fileName: finalFileName,
                createdAt: Date()
            )
            
            // Save to Firestore
            try await FirebaseService.shared.saveInvoice(userId: userId, invoice: invoice)
            
            // Dismiss and reload
            await MainActor.run {
                dismiss()
                onSave()
            }
        } catch {
            errorMessage = "Failed to save invoice: \(error.localizedDescription)"
            showingError = true
            isSaving = false
        }
    }
}

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                parent.imageData = imageData
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

