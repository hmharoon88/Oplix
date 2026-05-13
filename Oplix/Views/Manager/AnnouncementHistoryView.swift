//
//  AnnouncementHistoryView.swift
//  Oplix
//
//  Manager-side wrapper around `AnnouncementsListView` that loads the
//  history of broadcasts the manager has sent. Surfaces delivery /
//  read stats on each row via `showStats: true`.
//
//  Loaded once when the screen appears; not observed live because the
//  manager already sees fresh sends through the send flow.
//

import SwiftUI

struct AnnouncementHistoryView: View {
    let managerUserId: String
    let locations: [Location]
    
    @State private var announcements: [Announcement] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    private var locationNames: [String: String] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0.name) })
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient.ignoresSafeArea()
            
            if isLoading && announcements.isEmpty {
                ProgressView("Loading announcements…")
                    .foregroundColor(Theme.darkGray)
            } else if let errorMessage = errorMessage, announcements.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Could not load history")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Retry") {
                        Task { await load() }
                    }
                    .cloudButton()
                }
            } else {
                AnnouncementsListView(
                    announcements: announcements,
                    viewerUserId: managerUserId,
                    locationNames: locationNames,
                    showStats: true,
                    onMarkRead: nil
                )
            }
        }
        .navigationTitle("Sent")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            announcements = try await FirebaseService.shared.fetchAnnouncements(
                managerUserId: managerUserId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
