//
//  TaskImageCaptureView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct TaskImageCaptureView: View {
    let task: WorkTask
    let onImagesCaptured: ([Data], String?) -> Void
    let onCancel: () -> Void
    
    @State private var showingImagePicker = false
    @State private var capturedImages: [(id: UUID, image: UIImage)] = []
    @State private var previewImage: UIImage?
    @State private var showingPreview = false
    @State private var note: String = ""
    @FocusState private var noteFieldFocused: Bool
    /// Max characters we accept on the note. Kept short on purpose so this
    /// stays a quick "anything I should flag?" field instead of turning
    /// into a long-form report — managers will skim these, not read essays.
    private let noteCharacterLimit = 280
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 50))
                                .foregroundColor(Theme.cloudBlue)
                            
                            Text("Complete Task")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text(task.description)
                                .font(.body)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Text("Add photos to mark this task as complete")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top)
                        
                        // Add Photo Button
                        Button(action: {
                            showingImagePicker = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Photo")
                            }
                            .frame(maxWidth: .infinity)
                            .cloudButton()
                        }
                        .padding(.horizontal)
                        
                        // Images Grid
                        if !capturedImages.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Photos (\(capturedImages.count))")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .padding(.horizontal)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)
                                ], spacing: 10) {
                                    ForEach(capturedImages, id: \.id) { item in
                                        ZStack(alignment: .topTrailing) {
                                            // Image
                                            Button(action: {
                                                previewImage = item.image
                                                showingPreview = true
                                            }) {
                                                Image(uiImage: item.image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipped()
                                                    .cornerRadius(8)
                                            }
                                            
                                            // Delete Button
                                            Button(action: {
                                                capturedImages.removeAll { $0.id == item.id }
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Color.white)
                                                    .clipShape(Circle())
                                                    .font(.title3)
                                            }
                                            .offset(x: 5, y: -5)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }

                            // Optional note for the manager
                            noteSection

                            // Submit Button
                            Button(action: submit) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Done")
                                }
                                .frame(maxWidth: .infinity)
                                .cloudButton(backgroundColor: .green)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Task Completion")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteFieldFocused = false }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: Binding(
                    get: { nil },
                    set: { newImage in
                        if let newImage = newImage {
                            capturedImages.append((id: UUID(), image: newImage))
                        }
                    }
                ))
            }
            .sheet(isPresented: $showingPreview) {
                if let image = previewImage {
                    ImagePreviewView(image: image)
                }
            }
        }
    }

    /// "Add a note (optional)" block beneath the photo grid. Kept compact
    /// so it doesn't dominate the screen — it's a quick assist for the
    /// manager during review, not the main event.
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note (optional)")
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                Text("\(note.count)/\(noteCharacterLimit)")
                    .font(.caption2)
                    .foregroundColor(note.count >= noteCharacterLimit ? .red : .gray)
            }

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Anything the manager should know? e.g. ran out of paper towels, freezer at 8°F.")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $note)
                    .focused($noteFieldFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minHeight: 90)
                    .onChange(of: note) { _, newValue in
                        if newValue.count > noteCharacterLimit {
                            note = String(newValue.prefix(noteCharacterLimit))
                        }
                    }
            }
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }

    private func submit() {
        // Convert all images to Data
        var imageDataList: [Data] = []
        for item in capturedImages {
            // Resize to max 1024px and compress to 50% quality for faster upload
            if let resizedImage = item.image.resizedAndCompressed(maxDimension: 1024),
               let imageData = resizedImage.jpegData(compressionQuality: 0.5) {
                imageDataList.append(imageData)
            } else {
                // Fallback: use original image with lower quality
                if let imageData = item.image.jpegData(compressionQuality: 0.4) {
                    imageDataList.append(imageData)
                }
            }
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onImagesCaptured(imageDataList, trimmed.isEmpty ? nil : trimmed)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        
        // Check if camera is available, otherwise use photo library
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ImagePreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - UIImage Extension for Image Compression
extension UIImage {
    /// Resizes the image to a maximum dimension while maintaining aspect ratio
    /// - Parameters:
    ///   - maxDimension: Maximum width or height (whichever is larger)
    /// - Returns: Resized image (compression happens separately with jpegData)
    func resizedAndCompressed(maxDimension: CGFloat = 1024) -> UIImage? {
        // Calculate new size maintaining aspect ratio
        let size = self.size
        let aspectRatio = size.width / size.height
        var newSize: CGSize
        
        if size.width > size.height {
            // Landscape
            if size.width > maxDimension {
                newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                newSize = size
            }
        } else {
            // Portrait or square
            if size.height > maxDimension {
                newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
            } else {
                newSize = size
            }
        }
        
        // Only resize if needed
        guard newSize.width < size.width || newSize.height < size.height else {
            return self
        }
        
        // Resize the image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        
        return resizedImage
    }
}

#Preview {
    TaskImageCaptureView(
        task: WorkTask(
            id: "test",
            description: "Test task",
            assignedEmployeeIds: [],
            locationId: "loc1",
            employeeCompletions: [:]
        ),
        onImagesCaptured: { _, _ in },
        onCancel: { }
    )
}

