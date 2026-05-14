//
//  TaskStatusView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

// Audit hub for a single location, reached from Task Check → tap a location.
// Shows a location header card plus two large category cards (Recurring /
// Corrective). Tapping a card pushes a TaskCategoryStatusScreen for that
// category, which is where the actual rows + photos + edit/add flow live.
struct TaskStatusView: View {
    /// Firestore data-root user id (the manager who owns the location).
    /// Used to read/write tasks; identical to the signed-in user for
    /// executives, but for supervisors this is `employee.managerUserId`
    /// which differs from their auth id.
    let userId: String
    let location: Location
    /// Locations available to the create-task flow. Pass all locations for
    /// executives (full picker), or `[location]` for supervisors so
    /// create flows stay scoped to their own location.
    let allLocations: [Location]

    /// Auth id of the person actually doing the audit / review. Defaults to
    /// `userId` (executive flow), but is set to the supervisor's auth id
    /// when this view is reached from the Supervisor controls so photo
    /// approvals are attributed to the supervisor, not the manager root.
    let reviewerUserId: String

    /// Optional role of the person viewing this screen — forwarded into
    /// `LocationDetailViewModel` so it can apply role-aware data scoping
    /// (e.g. supervisors only see employees at their location).
    let currentUserRole: User.UserRole?

    // Dismisses the entire fullScreenCover from any depth — wired by
    // TaskCheckView and forwarded into pushed child screens so the bottom
    // "Done" button works from inside the category drilldown too.
    var onDone: () -> Void = {}

    @StateObject private var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(
        userId: String,
        location: Location,
        allLocations: [Location] = [],
        reviewerUserId: String? = nil,
        currentUserRole: User.UserRole? = nil,
        onDone: @escaping () -> Void = {}
    ) {
        self.userId = userId
        self.location = location
        self.allLocations = allLocations
        self.reviewerUserId = reviewerUserId ?? userId
        self.currentUserRole = currentUserRole
        self.onDone = onDone
        _viewModel = StateObject(
            wrappedValue: LocationDetailViewModel(
                userId: userId,
                locationId: location.id,
                currentUserRole: currentUserRole
            )
        )
    }

    private var recurringCount: Int {
        viewModel.tasks.filter { $0.frequency.isRecurring }.count
    }

    private var correctiveCount: Int {
        viewModel.tasks.filter { $0.frequency == .oneTime }.count
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading tasks...")
                        .foregroundColor(.secondary)
                        .padding()
                }
            } else if let error = errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Error Loading Tasks")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task { await loadTasks() }
                    }
                    .cloudButton()
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Location header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(location.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Text(location.address)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cloudWhite)
                        .cornerRadius(12)
                        .padding(.horizontal)

                        // Category cards
                        VStack(spacing: 16) {
                            NavigationLink(destination: TaskCategoryStatusScreen(
                                userId: userId,
                                location: location,
                                allLocations: allLocations,
                                category: .recurring,
                                viewModel: viewModel,
                                reviewerUserId: reviewerUserId,
                                onDone: onDone
                            )) {
                                categoryCard(category: .recurring, count: recurringCount)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: TaskCategoryStatusScreen(
                                userId: userId,
                                location: location,
                                allLocations: allLocations,
                                category: .corrective,
                                viewModel: viewModel,
                                reviewerUserId: reviewerUserId,
                                onDone: onDone
                            )) {
                                categoryCard(category: .corrective, count: correctiveCount)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Task Status")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            doneBar
        }
        .task {
            await loadTasks()
        }
    }

    // Bottom-anchored Done so it's reachable with one thumb from anywhere on
    // the audit hub, instead of stretching to the top-right toolbar.
    // `onDone` dismisses the executive full-screen flow (Task Check tab).
    // Supervisors don't pass `onDone`, so we always call `dismiss()` to pop
    // this hub back to Supervisor Controls.
    private var doneBar: some View {
        Button(action: {
            onDone()
            dismiss()
        }) {
            Text("Done")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.3, blue: 0.6),
                            Color(red: 0.15, green: 0.4, blue: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func categoryCard(category: TaskCategory, count: Int) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(category.tint.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: category.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(category.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(countText(count: count))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(category.tint)
                    .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private func countText(count: Int) -> String {
        if count == 0 { return "No tasks" }
        return "\(count) task\(count == 1 ? "" : "s")"
    }

    private func loadTasks() async {
        isLoading = true
        errorMessage = nil
        await viewModel.loadData()
        if let error = viewModel.errorMessage {
            errorMessage = error
        }
        isLoading = false
    }
}

// MARK: - Row used by TaskCategoryStatusScreen
struct TaskStatusRow: View {
    let task: WorkTask
    let employees: [Employee]
    // Optional callback for tap-to-edit. When nil, the row stays read-only.
    // The photo button inside is still wired to its own action so tapping a
    // photo opens the image viewer rather than the edit sheet.
    var onEditTap: (() -> Void)? = nil
    // Optional callback for manager photo-review. When non-nil the photo
    // viewer shows Approve / Disapprove buttons; tapping them fires this
    // closure so the parent screen can persist the change to Firestore.
    var onReview: ((_ employeeId: String, _ approved: Bool, _ note: String?) -> Void)? = nil

    @State private var selectedImage: ImageData?

    private func getEmployeeName(employeeId: String) -> String {
        employees.first(where: { $0.id == employeeId })?.name ?? "Unknown"
    }

    // For recurring tasks, only show completions from the current cycle so
    // yesterday's daily-task photos don't appear as today's status.
    private var visibleCompletions: [String: TaskCompletion] {
        task.currentCycleCompletions
    }

    // MARK: - Status helpers
    private var assignedCount: Int { task.assignedEmployeeIds.count }

    private var completedCount: Int {
        task.assignedEmployeeIds.filter { task.isCompletedBy(employeeId: $0) }.count
    }

    private var isFullyComplete: Bool {
        assignedCount > 0 && completedCount == assignedCount
    }

    private var isPartiallyComplete: Bool {
        completedCount > 0 && completedCount < assignedCount
    }

    private enum RowStatus {
        case unassigned, pending, partial, done
    }

    private var status: RowStatus {
        if assignedCount == 0 { return .unassigned }
        if isFullyComplete { return .done }
        if isPartiallyComplete { return .partial }
        return .pending
    }

    private var statusColor: Color {
        switch status {
        case .unassigned: return .gray
        case .pending: return .orange
        case .partial: return .orange
        case .done: return .green
        }
    }

    private var statusText: String {
        switch status {
        case .unassigned: return "UNASSIGNED"
        case .pending: return "PENDING"
        case .partial: return "\(completedCount)/\(assignedCount)"
        case .done: return "DONE"
        }
    }

    private var cyclePeriodLabel: String? {
        guard task.frequency.isRecurring else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        switch task.frequency {
        case .daily:
            return "Today, \(formatter.string(from: Date()))"
        case .weekly:
            return "This week (since \(formatter.string(from: task.currentCycleStart())))"
        case .monthly:
            return "This month (since \(formatter.string(from: task.currentCycleStart())))"
        case .oneTime:
            return nil
        }
    }

    private var assigneeNames: [String] {
        task.assignedEmployeeIds.compactMap { id in
            employees.first(where: { $0.id == id })?.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ─── Title row: description + frequency chip + status pill ───
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(task.description)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        if task.frequency.isRecurring {
                            Text(task.frequency.shortName.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.cloudBlue)
                                .cornerRadius(8)
                        }
                    }

                    if let cyclePeriodLabel = cyclePeriodLabel {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(cyclePeriodLabel)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                statusPill
            }

            // ─── Assignees ───
            assigneeRow

            // ─── Divider before completion state, only if there's more below ───
            if !visibleCompletions.isEmpty || (assignedCount > 0 && !isFullyComplete) {
                Divider().opacity(0.4)
            }

            // ─── Completions or empty state ───
            if !visibleCompletions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(visibleCompletions.keys.sorted()), id: \.self) { employeeId in
                        if let completion = visibleCompletions[employeeId] {
                            TaskCompletionCard(
                                employeeName: getEmployeeName(employeeId: employeeId),
                                completion: completion,
                                onImageTap: {
                                    let allURLs = completion.imageURLs.isEmpty ? [completion.imageURL] : completion.imageURLs
                                    selectedImage = ImageData(
                                        url: allURLs.first ?? completion.imageURL,
                                        imageURLs: allURLs,
                                        employeeName: getEmployeeName(employeeId: employeeId),
                                        employeeId: employeeId,
                                        timestamp: completion.timestamp,
                                        initialApprovalStatus: completion.isApproved,
                                        initialDisapprovalNote: completion.disapprovalNote
                                    )
                                }
                            )
                        }
                    }
                }
            } else if status == .pending {
                emptyPendingPill
            }
        }
        .padding(16)
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .overlay(
            // Soft tinted top accent line that mirrors the status colour.
            RoundedRectangle(cornerRadius: 16)
                .stroke(statusColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // The TaskCompletionCard's photo button is still a Button (it
            // wins the tap), so this only fires for taps on whitespace, the
            // description, the assignee line, etc. — i.e. anywhere that's
            // not a photo thumbnail.
            onEditTap?()
        }
        .sheet(item: $selectedImage) { imageData in
            // The sheet content is a snapshot of the photo at tap time. We
            // intentionally don't recompute `imageData` from the live tasks
            // array on every render — that's what caused the previous
            // dismiss/re-present cycle when the parent's task listener fired.
            //
            // When `onReview` is wired up (manager / supervisor flow), build
            // a `PhotoReviewConfig` so the viewer renders Approve /
            // Disapprove buttons. The review callback bubbles back up to
            // `TaskCategoryStatusScreen`, which persists the change.
            let reviewConfig: PhotoReviewConfig? = onReview.map { reviewClosure in
                PhotoReviewConfig(
                    currentStatus: imageData.initialApprovalStatus,
                    disapprovalNote: imageData.initialDisapprovalNote,
                    onReview: { approved, note in
                        reviewClosure(imageData.employeeId, approved, note)
                    }
                )
            }
            if imageData.imageURLs.count > 1 {
                TaskImagesView(
                    imageURLs: imageData.imageURLs,
                    timestamp: imageData.timestamp,
                    employeeName: imageData.employeeName,
                    review: reviewConfig
                )
            } else {
                TaskImageView(
                    imageURL: imageData.url,
                    timestamp: imageData.timestamp,
                    employeeName: imageData.employeeName,
                    review: reviewConfig
                )
            }
        }
    }

    // MARK: - Sub-views

    private var statusPill: some View {
        Text(statusText)
            .font(.system(size: 11, weight: .heavy))
            .foregroundColor(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private var assigneeRow: some View {
        if assigneeNames.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "person.slash")
                    .font(.caption2)
                Text("Unassigned")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(assigneeNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
    }

    private var emptyPendingPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
            Text(task.frequency.isRecurring ? "Not completed yet this cycle" : "Not completed")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct TaskCompletionCard: View {
    let employeeName: String
    let completion: TaskCompletion
    let onImageTap: () -> Void

    @State private var previewImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onImageTap) {
                    Group {
                        if let image = previewImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else if isLoading {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .overlay(ProgressView().scaleEffect(0.8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                    .clipped()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Completed by \(employeeName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }

                    Text(completion.timestamp, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(completion.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if completion.imageURLs.count > 1 {
                        Text("\(completion.imageURLs.count) photos - Tap to view")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else {
                        Text("Tap photo to view full size")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                Spacer()
            }

            if let note = completion.note?.trimmingCharacters(in: .whitespacesAndNewlines),
               !note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.bubble.fill")
                        .font(.caption)
                        .foregroundColor(Theme.cloudBlue)
                        .padding(.top, 2)
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cloudBlue.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .task {
            await loadPreviewImage()
        }
    }

    private func loadPreviewImage() async {
        let imageURLString = completion.imageURLs.first ?? completion.imageURL
        guard let url = URL(string: imageURLString) else {
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    previewImage = image
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        } catch {
            print("Failed to load preview image: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}

struct ImageData: Identifiable {
    // Stable, content-based id so SwiftUI's `.sheet(item:)` doesn't dismiss
    // and re-present when the parent view re-renders (e.g. when the manager
    // dashboard's task listener fires). Using `UUID()` here caused the photo
    // viewer to disappear and reappear in a tight loop — the listener pushed
    // an updated tasks array, the body re-ran, the binding handed SwiftUI a
    // new id, and the sheet replaced itself every cycle.
    var id: String { "\(url)|\(timestamp.timeIntervalSince1970)|\(employeeName)" }
    let url: String
    let imageURLs: [String]
    let employeeName: String
    /// Employee whose completion this photo belongs to. Captured at tap time
    /// so the review-callback knows which completion to mutate when the
    /// manager hits Approve / Disapprove.
    let employeeId: String
    let timestamp: Date
    /// Snapshot of the current review state at tap time. The viewer keeps
    /// its own local copy after that and updates optimistically on user
    /// action.
    let initialApprovalStatus: Bool?
    let initialDisapprovalNote: String?
}

#Preview {
    TaskStatusView(
        userId: "test-user",
        location: Location(
            id: "test-location",
            name: "Test Location",
            address: "123 Test St",
            managerId: "test-manager",
            employees: [],
            tasks: [],
            lotteryForms: []
        )
    )
}
