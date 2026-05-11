//
//  LocationSwitcherView.swift
//  Oplix
//
//  Login-time and in-session location picker for users who are
//  assigned to more than one location.
//

import SwiftUI

// MARK: - Environment plumbing
//
// Deeper screens (e.g. SupervisorControlsView) request a location switch
// by reading this environment value. The shell at EmployeeHomeView injects
// a closure that puts the app back into the picker state.

private struct LocationSwitchKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Closure that, when invoked, dismisses the current location-scoped
    /// session and re-presents the location picker. `nil` when the
    /// current user has only one assigned location (so deeper screens
    /// can hide the "Switch Location" affordance).
    var requestLocationSwitch: (() -> Void)? {
        get { self[LocationSwitchKey.self] }
        set { self[LocationSwitchKey.self] = newValue }
    }
}

// MARK: - Picker view

/// Full-screen location picker shown:
///   • At login when the user is assigned to ≥ 2 locations.
///   • In-session when a supervisor taps "Switch Location" on the
///     Supervisor tab — the shell flips its `activeLocationId` back to
///     `nil` and we land here again.
///
/// The picker intentionally has no "skip" or "default to last" affordance.
/// Per product decision, the user must explicitly choose every relaunch
/// so context is never ambiguous.
struct LocationPickerView: View {
    let userName: String
    let userRoleLabel: String
    let locations: [Location]
    /// Pre-highlight a location (used for in-session switching to bias
    /// the cursor toward the location the user is currently in).
    let preselectedLocationId: String?
    let onSelect: (String) -> Void
    let onLogout: () -> Void

    @State private var highlightedLocationId: String?

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .onAppear {
            if highlightedLocationId == nil {
                highlightedLocationId = preselectedLocationId ?? locations.first?.id
            }
        }
    }

    // MARK: Subviews

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                Text("Oplix")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("Logout", action: onLogout)
                    .foregroundColor(.white)
                    .font(.system(size: 16))
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome, \(userName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(userRoleLabel)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 50))
                        .foregroundColor(Theme.cloudBlue)
                    Text("Select Location")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    Text("You're assigned to \(locations.count) locations. Choose one to start your session.")
                        .font(.subheadline)
                        .foregroundColor(Theme.darkGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    ForEach(locations) { location in
                        locationRow(location)
                    }
                }
                .padding(.horizontal)

                if let selectedId = highlightedLocationId {
                    Button {
                        onSelect(selectedId)
                    } label: {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.cloudBlue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Spacer(minLength: 24)
            }
        }
    }

    @ViewBuilder
    private func locationRow(_ location: Location) -> some View {
        let isSelected = highlightedLocationId == location.id
        Button {
            highlightedLocationId = location.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Theme.cloudBlue : Theme.darkGray)

                VStack(alignment: .leading, spacing: 4) {
                    Text(location.name)
                        .font(.headline)
                        .foregroundColor(.black)
                    if !location.address.isEmpty {
                        Text(location.address)
                            .font(.caption)
                            .foregroundColor(Theme.darkGray)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding()
            .background(Theme.cloudWhite)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.cloudBlue : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Resolving error fallback

/// Inline error screen shown when the shell can't determine the user's
/// assigned locations (network failure, permissions issue, etc.). Keeps
/// users out of a force-unwrap crash — the original behaviour was a
/// `fatalError` if `user.locationId` was nil.
struct LocationResolveErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onLogout: () -> Void

    var body: some View {
        ZStack {
            Theme.secondaryGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                Text("Couldn't load your locations")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(Theme.darkGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                HStack(spacing: 12) {
                    Button("Retry", action: onRetry)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Theme.cloudBlue)
                        .cornerRadius(10)
                    Button("Logout", action: onLogout)
                        .font(.system(size: 16))
                        .foregroundColor(Theme.cloudBlue)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Theme.cloudWhite)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }
}
