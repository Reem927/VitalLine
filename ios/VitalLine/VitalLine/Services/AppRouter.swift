import Foundation
import Observation

// Every screen that can be pushed inside the Dispatch tab.
// To go to the next screen, call router.push(.indoorPlan) etc.
enum AppScreen: Hashable {
    case routePreview
    case liveNavigation
    case indoorPlan
    case arNavigation      // optional idea; placeholder only for now
    case completed
}

enum AppTab: Hashable {
    case dispatch, history, settings
}

// The ambulance this phone belongs to (shown in History).
enum Crew {
    static let unit = "M-12"
}

// Shared navigation state. Read it in any view with:
//   @Environment(AppRouter.self) private var router
@MainActor
@Observable
final class AppRouter {
    var path: [AppScreen] = []
    var selectedTab: AppTab = .dispatch

    func push(_ screen: AppScreen) { path.append(screen) }
    func popToRoot() { path.removeAll() }
}

// One saved response, shown in the History tab.
struct HistoryEntry: Identifiable {
    let id = UUID()
    let plan: Plan
    let events: [ResponseEvent]
    let crewUnit: String

    // When the call came in (first event), for sorting and the list row.
    var date: Date { events.first?.date ?? .now }

    // Arrived at building -> at patient, in minutes. nil if either is missing.
    var actualAccessMinutes: Double? {
        guard let start = events.first(where: { $0.kind == .arrivedAtBuilding })?.date,
              let end = events.first(where: { $0.kind == .atPatient })?.date else { return nil }
        return end.timeIntervalSince(start) / 60
    }
}

// In-memory history (resets when the app restarts; fine for the demo).
// Read it with: @Environment(HistoryStore.self) private var history
@MainActor
@Observable
final class HistoryStore {
    var entries: [HistoryEntry] = []

    func save(_ plan: Plan, events: [ResponseEvent]) {
        entries.insert(HistoryEntry(plan: plan, events: events, crewUnit: Crew.unit), at: 0)
    }
}
