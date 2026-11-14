import Foundation
import Observation

// Every screen that can be pushed inside the Dispatch tab.
// Person B: to go to the next screen, call router.push(.indoorPlan) etc.
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
    let date: Date
    let plan: Plan
}

// In-memory history (resets when the app restarts; fine for the demo).
// Read it with: @Environment(HistoryStore.self) private var history
@MainActor
@Observable
final class HistoryStore {
    var entries: [HistoryEntry] = []

    func save(_ plan: Plan) {
        entries.insert(HistoryEntry(date: .now, plan: plan), at: 0)
    }
}
