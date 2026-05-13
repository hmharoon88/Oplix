//
//  EmployeeAnnouncementsCard.swift
//  Oplix
//
//  Compact card on the employee/supervisor home screen that surfaces
//  the latest broadcast announcement from the manager. Shows just the
//  newest message with an unread blue dot when applicable, plus a
//  "View all" tap to open the full inbox.
//
//  Hidden when the user has zero announcements (keeps the home tidy
//  for new employees + locations that don't use broadcasts).
//

import SwiftUI

struct EmployeeAnnouncementsCard: View {
    let latest: Announcement
    let unreadCount: Int
    let viewerUserId: String
    let totalCount: Int
    let onTap: () -> Void
    
    private var isUnread: Bool {
        latest.isUnread(for: viewerUserId)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ANNOUNCEMENTS")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                if unreadCount > 0 {
                    Text("\(unreadCount) NEW")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                Spacer()
                if totalCount > 1 {
                    Text("View all")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.cloudBlue)
                }
            }
            
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "megaphone.fill")
                                .font(.system(size: 16, weight: .semibold))
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
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(latest.title)
                                .font(.system(size: 15, weight: isUnread ? .bold : .semibold))
                                .foregroundColor(.black)
                                .lineLimit(1)
                            Spacer()
                            Text(relativeDate(latest.sentAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(latest.body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .oplixCard()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
    
    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
