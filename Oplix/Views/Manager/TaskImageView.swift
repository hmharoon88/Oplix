//
//  TaskImageView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct TaskImageView: View {
    let imageURL: String
    let timestamp: Date?
    let employeeName: String?
    @Environment(\.dismiss) var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    init(imageURL: String, timestamp: Date?, employeeName: String? = nil) {
        self.imageURL = imageURL
        self.timestamp = timestamp
        self.employeeName = employeeName
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let image = image {
                    ZoomableImageView(image: image)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                        Text("Failed to load image")
                            .foregroundColor(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Completion Photo")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let employeeName = employeeName {
                        Text("Completed by: \(employeeName)")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    if let timestamp = timestamp {
                        VStack(spacing: 4) {
                            Text("Photo taken:")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text(timestamp, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Text(timestamp, style: .time)
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black.opacity(0.7))
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await loadImage()
            }
        }
    }
    
    private func loadImage() async {
        guard let url = URL(string: imageURL) else {
            errorMessage = "Invalid image URL"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let loadedImage = UIImage(data: data) {
                image = loadedImage
            } else {
                errorMessage = "Failed to decode image"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Zoomable Image View
struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private func calculateFittedSize(in geometry: GeometryProxy) -> CGSize {
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = geometry.size.width / geometry.size.height
        
        if imageAspectRatio > viewAspectRatio {
            // Image is wider - fit to width
            return CGSize(width: geometry.size.width, height: geometry.size.width / imageAspectRatio)
        } else {
            // Image is taller - fit to height
            return CGSize(width: geometry.size.height * imageAspectRatio, height: geometry.size.height)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let fittedSize = calculateFittedSize(in: geometry)
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fittedSize.width * scale, height: fittedSize.height * scale)
                .position(
                    x: geometry.size.width / 2 + offset.width,
                    y: geometry.size.height / 2 + offset.height
                )
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                let newScale = min(max(scale * delta, 1.0), 5.0)
                                scale = newScale
                                
                                // Reset offset if zooming out to fit
                                if newScale <= 1.0 {
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                // Snap back to minimum scale if needed
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if scale < 1.0 {
                                        scale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                // Only allow dragging when zoomed in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    // Double tap to zoom in/out
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                        }
                    }
                }
        }
    }
}

#Preview {
    TaskImageView(imageURL: "https://example.com/image.jpg", timestamp: Date())
}

