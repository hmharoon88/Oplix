//
//  DocumentsScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentsScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var showingAddDocument = false
    @State private var documentToDelete: Document?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.documents.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.indigo)
                    
                    Text("No Documents")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Tap the + button to upload a document")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(viewModel.documents) { document in
                        DocumentRow(document: document)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first {
                            documentToDelete = viewModel.documents[index]
                            showingDeleteConfirmation = true
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddDocument = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.cloudBlue)
                }
            }
        }
        .sheet(isPresented: $showingAddDocument) {
            AddDocumentView(viewModel: viewModel, userId: viewModel.userId)
        }
        .alert("Delete Document", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                documentToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let document = documentToDelete {
                    Task {
                        await viewModel.deleteDocument(document)
                        documentToDelete = nil
                    }
                }
            }
        } message: {
            if let document = documentToDelete {
                Text("Are you sure you want to delete '\(document.name)'? This action cannot be undone.")
            }
        }
    }
}

struct DocumentRow: View {
    let document: Document
    
    var body: some View {
        HStack(spacing: 16) {
            // Document Icon
            Image(systemName: iconForFileType(document.fileType))
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.8), Color.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(document.name)
                    .font(.headline)
                    .foregroundColor(.black)
                
                HStack(spacing: 12) {
                    Text(document.fileType.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let expiryDate = document.expiryDate {
                        if document.isExpired {
                            Label("Expired", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if document.isExpiringSoon {
                            Label("Expiring Soon", systemImage: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("Expires: \(formatDate(expiryDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Text("Uploaded: \(formatDate(document.uploadedAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let url = URL(string: document.fileURL) {
                Link(destination: url) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(Theme.cloudBlue)
                        .font(.title3)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func iconForFileType(_ fileType: String) -> String {
        let type = fileType.lowercased()
        if type == "pdf" {
            return "doc.fill"
        } else if ["jpg", "jpeg", "png", "gif"].contains(type) {
            return "photo.fill"
        } else if ["doc", "docx"].contains(type) {
            return "doc.text.fill"
        } else {
            return "doc.fill"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct AddDocumentView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    let userId: String
    @Environment(\.dismiss) var dismiss
    
    @State private var documentName: String = ""
    @State private var hasExpiry: Bool = false
    @State private var expiryDate: Date = Date()
    @State private var selectedFile: URL?
    @State private var fileData: Data?
    @State private var fileName: String = ""
    @State private var fileType: String = ""
    @State private var showingFilePicker = false
    @State private var showingCamera = false
    @State private var showingImagePicker = false
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Document Information") {
                        TextField("Document Name", text: $documentName)
                            .disabled(isUploading)
                    }
                    
                    Section("Upload Document") {
                        Button(action: {
                            showingFilePicker = true
                        }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                Text("Choose from Files")
                            }
                        }
                        .disabled(isUploading)
                        
                        Button(action: {
                            showingCamera = true
                        }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Take Photo")
                            }
                        }
                        .disabled(isUploading)
                        
                        Button(action: {
                            showingImagePicker = true
                        }) {
                            HStack {
                                Image(systemName: "photo.fill")
                                Text("Choose from Photos")
                            }
                        }
                        .disabled(isUploading)
                        
                        if let fileName = selectedFile?.lastPathComponent {
                            Text("Selected: \(fileName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section("Expiry Date") {
                        Toggle("Has Expiry Date", isOn: $hasExpiry)
                            .disabled(isUploading)
                        
                        if hasExpiry {
                            DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                                .disabled(isUploading)
                        }
                    }
                }
                .disabled(isUploading)
                
                // Loading overlay
                if isUploading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("Uploading document...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.7))
                    )
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        Task {
                            await uploadDocument()
                        }
                    }
                    .disabled(documentName.isEmpty || fileData == nil || isUploading)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result: result)
            }
            .sheet(isPresented: $showingCamera) {
                CameraPickerView(fileData: $fileData, fileName: $fileName, fileType: $fileType)
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePickerView(fileData: $fileData, fileName: $fileName, fileType: $fileType)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = uploadError {
                    Text(error)
                }
            }
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
                    uploadError = "Failed to access file. Please try again."
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
                } catch {
                    uploadError = "Failed to read file: \(error.localizedDescription)"
                    showingError = true
                }
            }
        case .failure(let error):
            uploadError = "Failed to select file: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func uploadDocument() async {
        guard let fileData = fileData, !documentName.isEmpty else {
            uploadError = "Please select a file and enter a document name"
            showingError = true
            return
        }
        
        isUploading = true
        uploadError = nil
        
        do {
            try await viewModel.createDocument(
                name: documentName,
                fileData: fileData,
                fileName: fileName.isEmpty ? "document" : fileName,
                fileType: fileType.isEmpty ? "pdf" : fileType,
                expiryDate: hasExpiry ? expiryDate : nil,
                uploadedBy: userId
            )
            dismiss()
        } catch {
            uploadError = "Failed to upload document: \(error.localizedDescription)"
            showingError = true
        }
        
        isUploading = false
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var fileData: Data?
    @Binding var fileName: String
    @Binding var fileType: String
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
        let parent: CameraPickerView
        
        init(_ parent: CameraPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                parent.fileData = imageData
                parent.fileName = "photo_\(Date().timeIntervalSince1970).jpg"
                parent.fileType = "jpeg"
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var fileData: Data?
    @Binding var fileName: String
    @Binding var fileType: String
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
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
                parent.fileData = imageData
                parent.fileName = "photo_\(Date().timeIntervalSince1970).jpg"
                parent.fileType = "jpeg"
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsScreen(viewModel: LocationDetailViewModel(userId: "test-user", locationId: "test-location"))
    }
}

