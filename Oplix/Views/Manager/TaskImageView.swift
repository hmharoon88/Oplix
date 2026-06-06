//
//  TaskImageView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

/// Optional manager-review config passed into the image viewers. When non-nil
/// the viewer renders an "Approve / Disapprove" action bar; tapping a button
/// fires `onReview(approved, note)`. `currentStatus` (true = approved, false
/// = disapproved, nil = not yet reviewed) lets the viewer show the existing
/// state if a review has already happened — so a manager can see they
/// already approved this and even change their mind.
struct PhotoReviewConfig {
    var currentStatus: Bool?
    var disapprovalNote: String?
    var onReview: (_ approved: Bool, _ note: String?) -> Void
}

struct TaskImageView: View {
    let imageURL: String
    let timestamp: Date?
    let employeeName: String?
    let review: PhotoReviewConfig?
    @Environment(\.dismiss) var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingDisapproveSheet = false
    @State private var disapprovalNoteDraft: String = ""
    @State private var localReviewStatus: Bool? = nil
    @State private var localDisapprovalNote: String? = nil

    init(imageURL: String, timestamp: Date?, employeeName: String? = nil, review: PhotoReviewConfig? = nil) {
        self.imageURL = imageURL
        self.timestamp = timestamp
        self.employeeName = employeeName
        self.review = review
        _localReviewStatus = State(initialValue: review?.currentStatus)
        _localDisapprovalNote = State(initialValue: review?.disapprovalNote)
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

                    // Manager-only review bar. Shown when the presenter
                    // passed in a `review` config (typically from the Task
                    // Check screen).
                    if review != nil {
                        PhotoReviewBar(
                            status: localReviewStatus,
                            disapprovalNote: localDisapprovalNote,
                            onApprove: { submitReview(approved: true, note: nil) },
                            onDisapprove: {
                                disapprovalNoteDraft = localDisapprovalNote ?? ""
                                showingDisapproveSheet = true
                            }
                        )
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
            .sheet(isPresented: $showingDisapproveSheet) {
                DisapprovalNoteSheet(
                    note: $disapprovalNoteDraft,
                    onSubmit: { note in
                        submitReview(approved: false, note: note.isEmpty ? nil : note)
                        showingDisapproveSheet = false
                    },
                    onCancel: { showingDisapproveSheet = false }
                )
            }
        }
    }

    private func submitReview(approved: Bool, note: String?) {
        localReviewStatus = approved
        localDisapprovalNote = approved ? nil : note
        review?.onReview(approved, note)
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
    @State private var isDragging = false
    
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
    
    @ViewBuilder
    var body: some View {
        GeometryReader { geometry in
            let fittedSize = calculateFittedSize(in: geometry)
            
            let imageView = Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fittedSize.width * scale, height: fittedSize.height * scale)
                .position(
                    x: geometry.size.width / 2 + offset.width,
                    y: geometry.size.height / 2 + offset.height
                )
                .simultaneousGesture(
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
                        }
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
            
            // Only add drag gesture when zoomed, allowing TabView to handle swipes when not zoomed
            if scale > 1.0 {
                imageView
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                isDragging = false
                                lastOffset = offset
                            }
                    )
            } else {
                imageView
            }
        }
        .contentShape(Rectangle()) // Make entire area tappable/swipeable
    }
}

// MARK: - Photo Review Bar

/// Visual approve / disapprove control shown in the photo viewer when a
/// manager opens it from Task Check. Renders a status pill on top showing
/// the current review state, then two big action buttons. Tapping
/// "Disapprove" doesn't fire immediately — the parent view shows a sheet
/// asking for an optional note first.
struct PhotoReviewBar: View {
    let status: Bool?
    let disapprovalNote: String?
    let onApprove: () -> Void
    let onDisapprove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Current status (only when a decision has been made).
            if let status = status {
                HStack(spacing: 8) {
                    Image(systemName: status ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundColor(status ? .green : .red)
                    Text(status ? "Approved" : "Disapproved")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())

                if status == false, let note = disapprovalNote, !note.isEmpty {
                    Text("Reason: \(note)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 12) {
                Button(action: onDisapprove) {
                    Label(status == false ? "Edit Reason" : "Disapprove", systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                }

                Button(action: onApprove) {
                    Label(status == true ? "Approved" : "Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(status == true ? Color.green.opacity(0.6) : Color.green.opacity(0.85))
                        .clipShape(Capsule())
                }
                .disabled(status == true)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Disapproval Note Sheet

struct DisapprovalNoteSheet: View {
    @Binding var note: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Optional note for the employee", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Why is this being disapproved?")
                } footer: {
                    Text("This message is shown to the employee so they know what to fix when they redo the task.")
                }
            }
            .navigationTitle("Disapprove Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Disapprove") {
                        onSubmit(note.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .foregroundColor(.red)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Multiple Images View
struct TaskImagesView: View {
    let imageURLs: [String]
    let timestamp: Date?
    let employeeName: String?
    let review: PhotoReviewConfig?
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex = 0
    @State private var images: [UIImage?] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingDisapproveSheet = false
    @State private var disapprovalNoteDraft: String = ""
    @State private var localReviewStatus: Bool? = nil
    @State private var localDisapprovalNote: String? = nil

    init(imageURLs: [String], timestamp: Date?, employeeName: String? = nil, review: PhotoReviewConfig? = nil) {
        self.imageURLs = imageURLs
        self.timestamp = timestamp
        self.employeeName = employeeName
        self.review = review
        _localReviewStatus = State(initialValue: review?.currentStatus)
        _localDisapprovalNote = State(initialValue: review?.disapprovalNote)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if !images.isEmpty {
                    VStack(spacing: 0) {
                        // Image viewer with swipe support
                        TabView(selection: $currentIndex) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                if let image = image {
                                    ZoomableImageView(image: image)
                                        .tag(index)
                                        .contentShape(Rectangle())
                                } else {
                                    VStack(spacing: 16) {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Loading image \(index + 1)...")
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .tag(index)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        
                        // Bottom info bar
                        VStack(spacing: 8) {
                            if let employeeName = employeeName {
                                Text("Completed by: \(employeeName)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            if imageURLs.count > 1 {
                                Text("Image \(currentIndex + 1) of \(imageURLs.count)")
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

                            // Review bar — same control as the single-image
                            // viewer. Approval applies to the whole
                            // submission (all photos), not per-image.
                            if review != nil {
                                PhotoReviewBar(
                                    status: localReviewStatus,
                                    disapprovalNote: localDisapprovalNote,
                                    onApprove: { submitReview(approved: true, note: nil) },
                                    onDisapprove: {
                                        disapprovalNoteDraft = localDisapprovalNote ?? ""
                                        showingDisapproveSheet = true
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.7))
                    }
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                        Text("Failed to load images")
                            .foregroundColor(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Completion Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await loadImages()
            }
            .sheet(isPresented: $showingDisapproveSheet) {
                DisapprovalNoteSheet(
                    note: $disapprovalNoteDraft,
                    onSubmit: { note in
                        submitReview(approved: false, note: note.isEmpty ? nil : note)
                        showingDisapproveSheet = false
                    },
                    onCancel: { showingDisapproveSheet = false }
                )
            }
        }
    }

    private func submitReview(approved: Bool, note: String?) {
        localReviewStatus = approved
        localDisapprovalNote = approved ? nil : note
        review?.onReview(approved, note)
    }

    private func loadImages() async {
        guard !imageURLs.isEmpty else {
            await MainActor.run {
                isLoading = false
                errorMessage = "No images to load"
            }
            return
        }
        
        await MainActor.run {
            images = Array(repeating: nil, count: imageURLs.count)
            isLoading = true
        }
        
        // Load all images in parallel
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, urlString) in imageURLs.enumerated() {
                group.addTask {
                    guard let url = URL(string: urlString) else {
                        return (index, nil)
                    }
                    
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            return (index, image)
                        }
                    } catch {
                        print("Failed to load image at index \(index): \(error)")
                    }
                    return (index, nil)
                }
            }
            
            for await (index, image) in group {
                await MainActor.run {
                    if index < images.count {
                        images[index] = image
                    }
                }
            }
        }
        
        await MainActor.run {
            isLoading = false
            if images.allSatisfy({ $0 == nil }) {
                errorMessage = "Failed to load any images"
            }
        }
    }
}

#Preview {
    TaskImageView(imageURL: "https://example.com/image.jpg", timestamp: Date())
}

