//
//  HomeLayoutPrefs.swift
//  Oplix
//
//  Per-device customization for the manager Home screen. Lets the user
//  hide sections they don't care about and reorder the ones they do.
//
//  Stored in UserDefaults (per-device, per-install). Keying on userId
//  so a shared device with multiple accounts doesn't blend layouts.
//
//  Greeting block is intentionally NOT toggleable — it's the screen's
//  identity (who you're logged in as, today's date) and removing it
//  would leave the screen feeling rootless.
//

import Foundation
import Combine

// MARK: - Section catalog

// Single source of truth for every section the manager Home can render.
// Adding a new togglable section?
//   1. Add a case here.
//   2. Add a default position in `HomeLayoutPrefs.defaultOrder`.
//   3. Render it in ManagerOverviewView's `section(for:)` switch.
enum HomeSection: String, CaseIterable, Identifiable, Codable {
    case actionCenter
    case thisWeek
    case lotteryToday
    case shortcuts
    case monthToDate
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .actionCenter: return "Needs Attention"
        case .thisWeek:     return "This Week"
        case .lotteryToday: return "Lottery Today"
        case .shortcuts:    return "Shortcuts"
        case .monthToDate:  return "Month to Date"
        }
    }
    
    var subtitle: String {
        switch self {
        case .actionCenter: return "Cash variances, overdue items, missing data"
        case .thisWeek:     return "Receivables and payables due in next 7 days"
        case .lotteryToday: return "Per-location lottery over/short for today"
        case .shortcuts:    return "Quick actions: shifts, payroll, status, broadcast"
        case .monthToDate:  return "Per-location sales, fuel, lottery, payroll, expenses"
        }
    }
    
    var icon: String {
        switch self {
        case .actionCenter: return "exclamationmark.triangle.fill"
        case .thisWeek:     return "calendar.badge.clock"
        case .lotteryToday: return "ticket.fill"
        case .shortcuts:    return "bolt.fill"
        case .monthToDate:  return "chart.bar.fill"
        }
    }
    
    var tint: String {
        switch self {
        case .actionCenter: return "orange"
        case .thisWeek:     return "purple"
        case .lotteryToday: return "yellow"
        case .shortcuts:    return "green"
        case .monthToDate:  return "indigo"
        }
    }
    
    /// True when the section has its own settings screen (per-section
    /// sub-customization) reachable by tapping the row body in
    /// `HomeCustomizationView`. Today only Needs Attention exposes this,
    /// but adding more is just: flip this to true and add a case to
    /// HomeCustomizationView's per-section navigation destination.
    var isCustomizable: Bool {
        switch self {
        case .actionCenter: return true
        default:            return false
        }
    }
}

// MARK: - Prefs payload

struct HomeLayoutPrefs: Codable, Equatable {
    var order: [HomeSection]
    var hidden: Set<HomeSection>
    /// Sub-customization for the "Needs Attention" (Action Center) section:
    /// alert categories the user wants to suppress on Home. The card itself
    /// can still be shown — this just trims which alert types appear inside it.
    /// Optional in the encoded form so old layouts decode cleanly.
    var hiddenAlertCategories: Set<ManagerAlertCategory> = []
    
    private enum CodingKeys: String, CodingKey {
        case order, hidden, hiddenAlertCategories
    }
    
    init(
        order: [HomeSection],
        hidden: Set<HomeSection>,
        hiddenAlertCategories: Set<ManagerAlertCategory> = []
    ) {
        self.order = order
        self.hidden = hidden
        self.hiddenAlertCategories = hiddenAlertCategories
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let orderRaw = (try? c.decode([String].self, forKey: .order)) ?? []
        self.order = orderRaw.compactMap { HomeSection(rawValue: $0) }
        let hiddenRaw = (try? c.decode([String].self, forKey: .hidden)) ?? []
        self.hidden = Set(hiddenRaw.compactMap { HomeSection(rawValue: $0) })
        self.hiddenAlertCategories =
            (try? c.decode(Set<ManagerAlertCategory>.self, forKey: .hiddenAlertCategories)) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(hiddenAlertCategories, forKey: .hiddenAlertCategories)
    }
    
    static let defaultOrder: [HomeSection] = [
        .actionCenter,
        .lotteryToday,
        .thisWeek,
        .shortcuts,
        .monthToDate,
    ]
    
    /// Previous default (before Today section was removed). Migrates saved
    /// layouts that still match this order exactly.
    static let legacyDefaultOrderWithToday: [HomeSection] = [
        .actionCenter,
        .lotteryToday,
        .thisWeek,
        .shortcuts,
        .monthToDate,
    ]
    
    static let `default` = HomeLayoutPrefs(
        order: defaultOrder,
        hidden: []
    )
    
    // The list to actually render — order respected, hidden sections dropped.
    // Falls back gracefully if a new section is added later: any case missing
    // from `order` is appended at the bottom so rolling out a new section
    // doesn't require migration.
    var visibleSectionsInOrder: [HomeSection] {
        var seen = Set<HomeSection>()
        var rendered: [HomeSection] = []
        for s in order where !hidden.contains(s) {
            if seen.insert(s).inserted { rendered.append(s) }
        }
        for s in HomeSection.allCases where !seen.contains(s) && !hidden.contains(s) {
            rendered.append(s)
        }
        return rendered
    }
}

// MARK: - Store

// Tiny ObservableObject that wraps UserDefaults so SwiftUI views can
// react to layout changes without manually re-reading the defaults.
// Per-user keying (`oplix.homeLayout.<userId>`) so accounts on a shared
// device don't pollute each other.
@MainActor
final class HomeLayoutStore: ObservableObject {
    @Published private(set) var prefs: HomeLayoutPrefs
    
    private let userId: String
    private let key: String
    
    /// Shared instances per-user so that the manager Home and the
    /// Settings → Home Layout screen mutate the SAME ObservableObject.
    /// Without this they each had their own copy and toggles in Settings
    /// wouldn't filter alerts on Home until the next app launch
    /// (because UserDefaults reads are one-shot at init).
    private static var instances: [String: HomeLayoutStore] = [:]
    
    static func shared(userId: String) -> HomeLayoutStore {
        if let existing = instances[userId] { return existing }
        let store = HomeLayoutStore(userId: userId)
        instances[userId] = store
        return store
    }
    
    /// Direct init kept private — callers go through `shared(userId:)`
    /// so all views observe the same store instance per user.
    private init(userId: String) {
        self.userId = userId
        self.key = "oplix.homeLayout.\(userId)"
        self.prefs = HomeLayoutStore.load(forKey: key)
    }
    
    func update(_ newPrefs: HomeLayoutPrefs) {
        prefs = newPrefs
        save(newPrefs)
    }
    
    func toggle(_ section: HomeSection) {
        var copy = prefs
        if copy.hidden.contains(section) {
            copy.hidden.remove(section)
        } else {
            copy.hidden.insert(section)
        }
        update(copy)
    }
    
    /// Flip a single Needs-Attention category on/off.
    func toggleAlertCategory(_ category: ManagerAlertCategory) {
        var copy = prefs
        if copy.hiddenAlertCategories.contains(category) {
            copy.hiddenAlertCategories.remove(category)
        } else {
            copy.hiddenAlertCategories.insert(category)
        }
        update(copy)
    }
    
    /// Show every category again — used by the "Reset" link inside the
    /// alert customization screen.
    func resetAlertCategories() {
        var copy = prefs
        copy.hiddenAlertCategories = []
        update(copy)
    }
    
    func move(from source: IndexSet, to destination: Int) {
        var copy = prefs
        copy.order.move(fromOffsets: source, toOffset: destination)
        update(copy)
    }
    
    func resetToDefault() {
        update(.default)
    }
    
    // MARK: - Persistence
    
    private func save(_ prefs: HomeLayoutPrefs) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
    
    private static func load(forKey key: String) -> HomeLayoutPrefs {
        guard let data = UserDefaults.standard.data(forKey: key),
              var decoded = try? JSONDecoder().decode(HomeLayoutPrefs.self, from: data) else {
            return .default
        }
        
        let original = decoded.order
        
        // Migration A — strip removed sections (e.g. legacy "today" raw value)
        // and normalize if the saved order matches a known legacy default.
        decoded.order = decoded.order.filter { HomeSection.allCases.contains($0) }
        decoded.hidden = decoded.hidden.filter { HomeSection.allCases.contains($0) }
        if decoded.order == HomeLayoutPrefs.legacyDefaultOrderWithToday {
            decoded.order = HomeLayoutPrefs.defaultOrder
        }
        
        // Migration B — generic "new section added since this layout was
        // saved" fix-up. Any HomeSection case missing from the saved
        // order is spliced in at the position it occupies in the current
        // defaultOrder, relative to whichever sibling is closest. This
        // way new sections land in a sensible default slot instead of
        // always being appended to the bottom (which is what
        // `visibleSectionsInOrder` used to do).
        decoded.order = spliceMissingSections(into: decoded.order)
        
        // Persist the migrated layout so it doesn't have to re-migrate
        // on every launch and so the customization screen reflects it.
        if decoded.order != original {
            if let encoded = try? JSONEncoder().encode(decoded) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
        return decoded
    }
    
    /// Splice any HomeSection case missing from `savedOrder` into the
    /// position it occupies in `defaultOrder`, relative to the nearest
    /// sibling that IS already in `savedOrder`. Preserves all of the
    /// user's existing positioning otherwise.
    ///
    /// Example: saved `[actionCenter, today, thisWeek, shortcuts, monthToDate]`,
    /// new section `.lotteryToday` (default index 2, between today + thisWeek)
    /// → result `[actionCenter, today, lotteryToday, thisWeek, shortcuts, monthToDate]`.
    private static func spliceMissingSections(into savedOrder: [HomeSection]) -> [HomeSection] {
        var result = savedOrder
        for section in HomeSection.allCases {
            if result.contains(section) { continue }
            
            guard let defaultIdx = HomeLayoutPrefs.defaultOrder.firstIndex(of: section) else {
                result.append(section)
                continue
            }
            
            // Walk backwards from this section's default neighbours
            // looking for the first one that already lives in `result`.
            // Insert immediately after it. If no earlier neighbour
            // exists, walk forward and insert immediately before. If
            // neither side resolves (empty result), append.
            var inserted = false
            
            // Search predecessors
            if defaultIdx > 0 {
                for i in stride(from: defaultIdx - 1, through: 0, by: -1) {
                    let candidate = HomeLayoutPrefs.defaultOrder[i]
                    if let pos = result.firstIndex(of: candidate) {
                        result.insert(section, at: pos + 1)
                        inserted = true
                        break
                    }
                }
            }
            // Fall back to successors
            if !inserted, defaultIdx < HomeLayoutPrefs.defaultOrder.count - 1 {
                for i in (defaultIdx + 1)..<HomeLayoutPrefs.defaultOrder.count {
                    let candidate = HomeLayoutPrefs.defaultOrder[i]
                    if let pos = result.firstIndex(of: candidate) {
                        result.insert(section, at: pos)
                        inserted = true
                        break
                    }
                }
            }
            if !inserted {
                result.append(section)
            }
        }
        return result
    }
}
