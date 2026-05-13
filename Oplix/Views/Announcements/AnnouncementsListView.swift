//
//  AnnouncementsListView.swift
//  Oplix
//
//  Shared inbox-style list of announcements. Rendered with the same
//  visual language for both roles, but the supplied callbacks differ:
//
//   • Employee / Supervisor: passes their own filtered announcements
//     (already addressed to them) + an `onMarkRead` callback.
//   • Manager: passes every announcement they've sent; `onMarkRead`
//     is a no-op, and the row UI reveals additional delivery/read
//     stats via `showStats`.
//

import SwiftUI

struct AnnouncementsListView: View {
    let announcements: [Announcement]
    /// The user opening the list. Drives the read/unread visual state
    /// of each row. For the manager-side history this is the manager
    /// themselves, who's never in `recipientIds`, so every row reads
    /// as already-read (which is the intent for the author view).
    let viewerUserId: String
    /// Authors lookup `userId → displayName` so each row can show
    /// "from {name}". Optional — when nil rows just say "From manager".
    var authorNames: [String: String] = [:]
    /// Location name lookup so the per-location chip can render. Empty
    /// dictionary is fine — rows just won't show the chip.
    var locationNames: [String: String] = [:]
    /// When `true`, each row shows recipient + read-count stats (used
    /// in the manager history view).
    var showStats: Bool = false
    /// Invoked when a row is tapped. Used by the employee viewmodel to
    /// stamp the `readBy[userId]` timestamp. Manager view passes nil.
    var onMarkRead: ((Announcement) async -> Void)? = nil
    
    @State private var selected: Announcement?
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient.ignoresSafeArea()
            
            if announcements.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(announcements) { announcement in
                            Button {
                                selected = announcement
                                if let onMarkRead = onMarkRead {
                                    Task { await onMarkRead(announcement) }
                                }
                            } label: {
                                AnnouncementRow(
                                    announcement: announcement,
                                    viewerUserId: viewerUserId,
                                    authorName: authorNames[announcement.authorId],
                                    locationName: announcement.locationId.flatMap { locationNames[$0] },
                                    showStats: showStats
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { announcement in
            AnnouncementDetailView(
                announcement: announcement,
                authorName: authorNames[announcement.authorId],
                locationName: announcement.locationId.flatMap { locationNames[$0] }
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "megaphone")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No announcements yet")
                .font(.headline)
                .foregroundColor(.black)
            Text("Broadcast messages from your manager will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Row

private struct AnnouncementRow: View {
    let announcement: Announcement
    let viewerUserId: String
    let authorName: String?
    let locationName: String?
    let showStats: Bool
    
    private var isUnread: Bool {
        announcement.isUnread(for: viewerUserId)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread dot + icon column. The blue dot only renders for
            // unread rows so the eye is drawn to fresh messages.
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.orange)
                }
                if isUnread {
                    Circle()
                        .fill(Theme.cloudBlue)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.cloudWhite, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(announcement.title)
                        .font(.system(size: 16, weight: isUnread ? .bold : .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Spacer()
                    Text(relativeDate(announcement.sentAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(announcement.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 6) {
                    if let locationName = locationName {
                        chip(text: locationName, icon: "mappin.circle.fill", color: .indigo)
                    } else {
                        chip(text: "All employees", icon: "person.3.fill", color: .blue)
                    }
                    if let authorName = authorName {
                        chip(text: "from \(authorName)", icon: "person.circle.fill", color: .gray)
                    }
                    Spacer()
                }
                .padding(.top, 4)
                
                if showStats {
                    statsRow
                        .padding(.top, 4)
                }
            }
        }
        .padding(14)
        .oplixCard()
    }
    
    private var statsRow: some View {
        HStack(spacing: 12) {
            Label("\(announcement.recipientIds.count) sent", systemImage: "paperplane.fill")
                .font(.caption2)
                .foregroundColor(.secondary)
            Label("\(announcement.readCount) read", systemImage: "eye.fill")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func chip(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Detail

struct AnnouncementDetailView: View {
    let announcement: Announcement
    let authorName: String?
    let locationName: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Metadata chips
                        HStack(spacing: 6) {
                            if let locationName = locationName {
                                chip(text: locationName, icon: "mappin.circle.fill", color: .indigo)
                            } else {
                                chip(text: "All employees", icon: "person.3.fill", color: .blue)
                            }
                            if let authorName = authorName {
                                chip(text: "from \(authorName)", icon: "person.circle.fill", color: .gray)
                            }
                        }
                        
                        // Title + sent timestamp
                        VStack(alignment: .leading, spacing: 6) {
                            Text(announcement.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                            Text(absoluteDate(announcement.sentAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Body text — selectable so users can copy a
                        // confirmation number / address / etc.
                        Text(announcement.body)
                            .font(.body)
                            .foregroundColor(.black)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .oplixCard()
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func chip(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private func absoluteDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
