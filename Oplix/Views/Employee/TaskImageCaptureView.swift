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
    let onImageCaptured: (Data) -> Void
    let onCancel: () -> Void
    
    @State private var showingImagePicker = false
    @State private var capturedImage: UIImage?
    @State private var showingPreview = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.cloudBlue)
                    
                    Text("Complete Task")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text(task.description)
                        .font(.body)
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Take a photo to mark this task as complete")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Take Photo")
                        }
                        .frame(maxWidth: .infinity)
                        .cloudButton()
                    }
                    .padding(.horizontal)
                    
                    if let image = capturedImage {
                        Button(action: {
                            showingPreview = true
                        }) {
                            HStack {
                                Image(systemName: "photo.fill")
                                Text("View Photo")
                            }
                            .frame(maxWidth: .infinity)
                            .cloudButton(backgroundColor: Theme.sunshineYellow)
                        }
                        .padding(.horizontal)
                        
                        Button(action: {
                            // Resize to max 1024px and compress to 50% quality for faster upload
                            if let resizedImage = image.resizedAndCompressed(maxDimension: 1024),
                               let imageData = resizedImage.jpegData(compressionQuality: 0.5) {
                                onImageCaptured(imageData)
                            } else {
                                // Fallback: use original image with lower quality
                                if let imageData = image.jpegData(compressionQuality: 0.4) {
                                    onImageCaptured(imageData)
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Submit")
                            }
                            .frame(maxWidth: .infinity)
                            .cloudButton(backgroundColor: .green)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Task Completion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $capturedImage)
            }
            .sheet(isPresented: $showingPreview) {
                if let image = capturedImage {
                    ImagePreviewView(image: image)
                }
            }
        }
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
        onImageCaptured: { _ in },
        onCancel: { }
    )
}

