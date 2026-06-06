//
//  SendAnnouncementView.swift
//  Oplix
//
//  Manager-facing screen to compose and send a push notification to
//  employees. Calls the `sendAnnouncement` Cloud Function (see
//  functions/announcements/sendAnnouncement.js). The recipient list
//  is resolved server-side based on locationId — the client only
//  picks scope (all employees / single location).
//

import SwiftUI
import FirebaseFunctions

struct SendAnnouncementView: View {
    let userId: String
    let locations: [Location]
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var messageBody: String = ""
    @State private var selectedLocationId: String? = nil
    @State private var isSending: Bool = false
    @State private var resultMessage: String? = nil
    @State private var resultIsError: Bool = false
    @State private var showingHistory: Bool = false

    private let titleLimit = 80
    private let bodyLimit = 500

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient.ignoresSafeArea(edges: .top)

                VStack(spacing: 0) {
                    headerBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            audienceCard
                            titleField
                            bodyField
                            sendButton
                            historyLink
                            if let resultMessage = resultMessage {
                                resultBanner(text: resultMessage, isError: resultIsError)
                            }
                            disclaimer
                        }
                        .padding()
                        .padding(.bottom, 60)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showingHistory) {
                AnnouncementHistoryView(
                    managerUserId: userId,
                    locations: locations
                )
            }
        }
    }
    
    private var historyLink: some View {
        Button {
            showingHistory = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                Text("View past announcements")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Theme.cloudBlue)
            .padding()
            .background(Theme.cloudWhite)
            .cornerRadius(12)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            Spacer()
            Text("Send Announcement")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.3, blue: 0.6),
                    Color(red: 0.15, green: 0.4, blue: 0.7)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Audience picker

    private var audienceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUDIENCE")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
                .tracking(0.5)

            Menu {
                Button {
                    selectedLocationId = nil
                } label: {
                    HStack {
                        Text("All employees")
                        if selectedLocationId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(locations) { loc in
                    Button {
                        selectedLocationId = loc.id
                    } label: {
                        HStack {
                            Text(loc.name)
                            if selectedLocationId == loc.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: selectedLocationId == nil ? "person.3.fill" : "mappin.circle.fill")
                        .foregroundColor(Theme.cloudBlue)
                    Text(audienceLabel)
                        .foregroundColor(.black)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Theme.cloudWhite)
                .cornerRadius(12)
            }
        }
    }

    private var audienceLabel: String {
        if let locationId = selectedLocationId,
           let loc = locations.first(where: { $0.id == locationId }) {
            return loc.name
        }
        return "All employees"
    }

    // MARK: - Title / body fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TITLE").font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.secondary).tracking(0.5)
                Spacer()
                Text("\(title.count)/\(titleLimit)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            TextField("e.g. Closing early today", text: $title)
                .padding()
                .background(Theme.cloudWhite)
                .cornerRadius(12)
                .onChange(of: title) { newValue in
                    if newValue.count > titleLimit {
                        title = String(newValue.prefix(titleLimit))
                    }
                }
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MESSAGE").font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.secondary).tracking(0.5)
                Spacer()
                Text("\(messageBody.count)/\(bodyLimit)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            // Multi-line text editor with a subtle border. The min
            // height keeps it tall enough to feel like a real text
            // area on first sight rather than a single-line field.
            TextEditor(text: $messageBody)
                .frame(minHeight: 140)
                .padding(8)
                .background(Theme.cloudWhite)
                .cornerRadius(12)
                .onChange(of: messageBody) { newValue in
                    if newValue.count > bodyLimit {
                        messageBody = String(newValue.prefix(bodyLimit))
                    }
                }
        }
    }

    // MARK: - Send

    private var sendButton: some View {
        Button(action: sendAnnouncement) {
            HStack {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSending ? "Sending…" : "Send Announcement")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSend ? Theme.cloudBlue : Color.gray.opacity(0.4))
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(!canSend || isSending)
    }

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resultBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.black)
            Spacer()
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }

    private var disclaimer: some View {
        Text("Recipients who have push notifications turned off, or who are in quiet hours, won't get a banner — but the message will still appear in their in-app Announcements inbox.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    private func sendAnnouncement() {
        guard canSend else { return }
        isSending = true
        resultMessage = nil

        // Payload — only include locationId if a specific location is picked.
        var payload: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "body": messageBody.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if let locationId = selectedLocationId {
            payload["locationId"] = locationId
        }

        Functions.functions().httpsCallable("sendAnnouncement").call(payload) { result, error in
            DispatchQueue.main.async {
                isSending = false
                if let error = error {
                    resultIsError = true
                    resultMessage = "Failed to send: \(error.localizedDescription)"
                    return
                }
                let data = result?.data as? [String: Any] ?? [:]
                let delivered = data["delivered"] as? Int ?? 0
                let recipients = data["recipients"] as? Int ?? 0
                resultIsError = false
                if recipients == 0 {
                    resultMessage = "No employees match this audience."
                } else {
                    resultMessage = "Delivered to \(delivered) of \(recipients) recipient\(recipients == 1 ? "" : "s")."
                }
                title = ""
                messageBody = ""
            }
        }
    }
}
