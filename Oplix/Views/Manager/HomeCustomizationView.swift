//
//  HomeCustomizationView.swift
//  Oplix
//
//  Settings sub-screen that lets the manager toggle Home sections on/off
//  and reorder them. Lives at Settings → Preferences → Home Layout.
//
//  Persistence is handled by HomeLayoutStore (UserDefaults, per-user).
//  ManagerOverviewView reads the same store and renders sections in the
//  user's chosen order, skipping anything they hid.
//

import SwiftUI

struct HomeCustomizationView: View {
    @ObservedObject var store: HomeLayoutStore
    @State private var editMode: EditMode = .active
    @State private var showingResetConfirmation = false
    /// Drives navigation into a section's per-section settings screen.
    /// Set when the user taps the row body of a customizable section.
    @State private var customizingSection: HomeSection?
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient.ignoresSafeArea()
            
            List {
                headerSection
                sectionsSection
                resetSection
                helpSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
        }
        .navigationTitle("Home Layout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $customizingSection) { section in
            // Per-section sub-customization. Add cases here as more
            // sections grow inner settings.
            switch section {
            case .actionCenter:
                NeedsAttentionCustomizationView(store: store)
            default:
                EmptyView()
            }
        }
        .alert("Reset Home Layout?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                store.resetToDefault()
            }
        } message: {
            Text("Restores the default order and shows every section.")
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Customize your Home screen")
                    .font(.headline)
                    .foregroundColor(.black)
                Text("Drag the handle to reorder. Toggle a section off to hide it. Tap the row to customize what shows inside.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var sectionsSection: some View {
        Section("Sections") {
            ForEach(store.prefs.order) { section in
                row(for: section)
            }
            .onMove { source, dest in
                store.move(from: source, to: dest)
            }
        }
    }
    
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to default")
                }
            }
        }
    }
    
    private var helpSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Greeting and chips always show", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("Settings are per device", systemImage: "iphone")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Row
    
    @ViewBuilder
    private func row(for section: HomeSection) -> some View {
        let isVisible = !store.prefs.hidden.contains(section)
        HStack(spacing: 12) {
            // Tap target: the entire row content (icon + title + subtitle).
            // Wrapped in a Button only when the section actually has
            // somewhere to navigate to — otherwise the row is static and
            // the toggle is the sole control. The toggle stays as a
            // sibling to the Button, so toggle taps don't trigger
            // navigation.
            if section.isCustomizable {
                Button {
                    customizingSection = section
                } label: {
                    rowBody(for: section)
                }
                .buttonStyle(.plain)
            } else {
                rowBody(for: section)
            }
            
            Spacer(minLength: 8)
            
            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { newVal in
                    if newVal == isVisible { return }
                    store.toggle(section)
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
    
    /// Just the icon + title (+ chevron when navigable) + subtitle.
    /// Pulled out so we can wrap it in a Button for customizable
    /// sections without duplicating layout.
    @ViewBuilder
    private func rowBody(for section: HomeSection) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tintColor(for: section).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tintColor(for: section))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    if section.isCustomizable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                Text(subtitle(for: section))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        // Make the whole row body — including padding — register taps,
        // so users don't have to land precisely on text.
        .contentShape(Rectangle())
    }
    
    /// Subtitle uses the section's own description, except for
    /// customizable sections where we surface the live count of inner
    /// settings (e.g. "All 9 categories on / 7 of 9 on") so users
    /// know there's something to tap into without opening it first.
    private func subtitle(for section: HomeSection) -> String {
        switch section {
        case .actionCenter:
            let total = ManagerAlertCategory.allCases.count
            let hidden = store.prefs.hiddenAlertCategories.count
            let visible = total - hidden
            return hidden == 0
                ? "All \(total) categories on"
                : "\(visible) of \(total) categories on"
        default:
            return section.subtitle
        }
    }
    
    private func tintColor(for section: HomeSection) -> Color {
        switch section.tint {
        case "orange": return .orange
        case "blue":   return .blue
        case "purple": return .purple
        case "green":  return .green
        case "indigo": return .indigo
        case "yellow": return .yellow
        default:       return Theme.cloudBlue
        }
    }
}

// MARK: - Needs Attention category toggles

/// Per-category visibility for the manager's Needs Attention card.
/// Toggling here mutates the same HomeLayoutStore the parent screen
/// uses, so the manager Home reflects changes the next time it renders.
struct NeedsAttentionCustomizationView: View {
    @ObservedObject var store: HomeLayoutStore
    @State private var showingResetConfirmation = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient.ignoresSafeArea()
            
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose what shows up")
                            .font(.headline)
                            .foregroundColor(.black)
                        Text("Toggle a category off to suppress those alerts on Home. Notifications and the underlying data are unaffected.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Categories") {
                    ForEach(ManagerAlertCategory.allCases) { category in
                        row(for: category)
                    }
                }
                
                if !store.prefs.hiddenAlertCategories.isEmpty {
                    Section {
                        Button {
                            showingResetConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Show all categories")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Needs Attention")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Show all alert categories?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Show all") { store.resetAlertCategories() }
        }
    }
    
    @ViewBuilder
    private func row(for category: ManagerAlertCategory) -> some View {
        let isVisible = !store.prefs.hiddenAlertCategories.contains(category)
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { newVal in
                    if newVal == isVisible { return }
                    store.toggleAlertCategory(category)
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
