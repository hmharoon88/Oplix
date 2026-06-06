//
//  ActionCenterCard.swift
//  Oplix
//
//  "Needs Attention" card for the manager Home screen. Renders the
//  alerts produced by HomeAlertsViewModel as tappable rows.
//

import SwiftUI

struct ActionCenterCard: View {
    let alerts: [ActionAlert]
    let isLoading: Bool
    // Caller is responsible for actually routing — we just hand back the alert.
    let onTapAlert: (ActionAlert) -> Void
    let onAcknowledge: (ActionAlert) -> Void

    // Cap the row count so a noisy location doesn't push everything else
    // off-screen; the rest are available via "Show all" below.
    @State private var showingAll: Bool = false
    private let collapsedLimit = 5

    private var visibleAlerts: [ActionAlert] {
        showingAll ? alerts : Array(alerts.prefix(collapsedLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isLoading && alerts.isEmpty {
                loadingRow
            } else if alerts.isEmpty {
                allCaughtUpRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleAlerts.enumerated()), id: \.element.id) { idx, alert in
                        alertRow(alert: alert)
                        if idx < visibleAlerts.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                    if alerts.count > collapsedLimit {
                        Divider().padding(.leading, 52)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingAll.toggle()
                            }
                        } label: {
                            HStack {
                                Text(showingAll ? "Show less" : "Show \(alerts.count - collapsedLimit) more")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.cloudBlue)
                                Spacer()
                                Image(systemName: showingAll ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.cloudBlue)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .oplixCard()
    }

    @ViewBuilder
    private func alertRow(alert: ActionAlert) -> some View {
        HStack(spacing: 0) {
            Button { onTapAlert(alert) } label: {
                AlertRow(alert: alert)
            }
            .buttonStyle(.plain)

            Button {
                onAcknowledge(alert)
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.cloudBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Acknowledge")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Needs Attention")
                .font(.headline)
                .foregroundColor(.black)
            Spacer()
            if !alerts.isEmpty {
                Text("\(alerts.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var allCaughtUpRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("All caught up")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text("Nothing needs you right now")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var loadingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Checking…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Single alert row

private struct AlertRow: View {
    let alert: ActionAlert

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Severity dot — same colored circle pattern used elsewhere
            // (e.g. the location card recurring badge) so visual language is consistent.
            Circle()
                .fill(alert.severity.tint)
                .frame(width: 12, height: 12)
                .padding(.leading, 4)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let sub = alert.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // No chevron when the row has no destination — keeps the visual
            // promise that everything with a > is tappable into a fix screen.
            if alert.route != .noAction {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
