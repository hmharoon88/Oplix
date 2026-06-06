//
//  TaskCompletionHistoryList.swift
//  Oplix
//
//  Date-grouped assignment audit for Task Check (Recurring / Corrective).
//

import SwiftUI

enum TaskCategoryListMode: String, CaseIterable {
    case current = "Current"
    case history = "History"
}

struct TaskCompletionHistoryList: View {
    let tasks: [WorkTask]
    let employees: [Employee]
    let categoryTint: Color
    var onReview: ((_ task: WorkTask, _ employeeId: String, _ completionTimestamp: Date, _ approved: Bool, _ note: String?) -> Void)? = nil

    private var daySections: [TaskAssignmentAudit.DaySection] {
        TaskAssignmentAudit.sections(from: tasks)
    }

    var body: some View {
        if daySections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.darkGray)
                Text("No assignment history yet")
                    .font(.subheadline)
                    .foregroundColor(Theme.darkGray)
                    .multilineTextAlignment(.center)
                Text("Past \(TaskAssignmentAudit.lookbackDays) days of assigned work, completions, and missed tasks will appear here grouped by date.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(daySections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        TaskHistoryDayHeader(
                            date: section.date,
                            assignedCount: section.assignedCount,
                            doneCount: section.doneCount,
                            missedCount: section.missedCount,
                            tint: categoryTint
                        )

                        if !section.doneEntries.isEmpty {
                            ForEach(section.doneEntries) { entry in
                                TaskCompletionHistoryRow(
                                    entry: entry,
                                    employeeName: employeeName(for: entry.completion.employeeId),
                                    onReview: onReview
                                )
                            }
                        }

                        ForEach(section.missedSlots) { slot in
                            TaskMissedHistoryRow(
                                task: slot.task,
                                employeeName: employeeName(for: slot.employeeId)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func employeeName(for employeeId: String) -> String {
        employees.first(where: { $0.id == employeeId })?.name ?? "Unknown"
    }
}

private struct TaskHistoryDayHeader: View {
    let date: Date
    let assignedCount: Int
    let doneCount: Int
    let missedCount: Int
    let tint: Color

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(tint)
                if isToday {
                    Text("Today")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.15))
                        .cornerRadius(6)
                }
            }

            HStack(spacing: 12) {
                HistoryStatPill(label: "Assigned", value: assignedCount, color: tint)
                HistoryStatPill(label: "Done", value: doneCount, color: .green)
                HistoryStatPill(label: "Missed", value: missedCount, color: missedCount > 0 ? .red : Theme.darkGray)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct HistoryStatPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct TaskMissedHistoryRow: View {
    let task: WorkTask
    let employeeName: String

    private var frequencyLabel: String? {
        task.frequency.isRecurring ? task.frequency.shortName : nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundColor(.red)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.description)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(employeeName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text("MISSED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)

                    if let frequencyLabel {
                        Text(frequencyLabel.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.cloudBlue)
                            .cornerRadius(6)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}

private struct TaskCompletionHistoryRow: View {
    let entry: TaskCompletionHistoryEntry
    let employeeName: String
    var onReview: ((_ task: WorkTask, _ employeeId: String, _ completionTimestamp: Date, _ approved: Bool, _ note: String?) -> Void)? = nil

    @State private var selectedImage: ImageData?

    private var frequencyLabel: String? {
        entry.task.frequency.isRecurring ? entry.task.frequency.shortName : nil
    }

    private var reviewLabel: String? {
        switch entry.completion.isApproved {
        case .some(true): return "Approved"
        case .some(false): return "Disapproved"
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.task.description)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text("DONE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(6)

                        if let frequencyLabel {
                            Text(frequencyLabel.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.cloudBlue)
                                .cornerRadius(6)
                        }
                        if let reviewLabel {
                            Text(reviewLabel.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(entry.completion.isApproved == false ? .red : .green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (entry.completion.isApproved == false ? Color.red : Color.green).opacity(0.12)
                                )
                                .cornerRadius(6)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(entry.completion.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TaskCompletionCard(
                employeeName: employeeName,
                completion: entry.completion,
                onImageTap: {
                    let urls = entry.completion.imageURLs.isEmpty
                        ? [entry.completion.imageURL]
                        : entry.completion.imageURLs
                    selectedImage = ImageData(
                        url: urls.first ?? entry.completion.imageURL,
                        imageURLs: urls,
                        employeeName: employeeName,
                        employeeId: entry.completion.employeeId,
                        timestamp: entry.completion.timestamp,
                        initialApprovalStatus: entry.completion.isApproved,
                        initialDisapprovalNote: entry.completion.disapprovalNote
                    )
                }
            )
        }
        .padding(16)
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .sheet(item: $selectedImage) { imageData in
            let reviewConfig: PhotoReviewConfig? = onReview.map { review in
                PhotoReviewConfig(
                    currentStatus: imageData.initialApprovalStatus,
                    disapprovalNote: imageData.initialDisapprovalNote,
                    onReview: { approved, note in
                        review(
                            entry.task,
                            imageData.employeeId,
                            imageData.timestamp,
                            approved,
                            note
                        )
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
}
