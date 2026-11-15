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
    var id = UUID().uuidString     // the backend's dispatch id when known
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

// Saved responses. With the live backend they come from GET /history/full (stored in
// Supabase), so they survive app restarts. A response saved a moment ago is shown at once
// and replaced by the backend's copy on the next refresh.
// Read it with: @Environment(HistoryStore.self) private var history
@MainActor
@Observable
final class HistoryStore {
    var entries: [HistoryEntry] = []
    var loadError: String?

    func save(_ plan: Plan, events: [ResponseEvent], dispatchId: String?) {
        entries.insert(HistoryEntry(id: dispatchId ?? UUID().uuidString, plan: plan,
                                    events: events, crewUnit: Crew.unit), at: 0)
    }

    func refresh() async {
        guard !API.useMock else { return }
        do {
            let saved = try await API.savedHistory().map(Self.entry)
            let known = Set(saved.map(\.id))
            entries = entries.filter { !known.contains($0.id) } + saved   // keep just-saved ones
            entries.sort { $0.date > $1.date }
            loadError = nil
        } catch {
            loadError = "Could not load saved responses."
        }
    }

    private static func entry(_ record: API.HistoryRecord) -> HistoryEntry {
        let kinds: [String: ResponseEvent.Kind] = [
            "dispatch_received": .dispatchReceived, "acknowledged": .enRoute,
            "arrived_building": .arrivedAtBuilding, "entered_lobby": .enteredLobby,
            "route_updated": .routeUpdated, "at_patient": .atPatient,
        ]
        let events = record.events.compactMap { row -> ResponseEvent? in
            guard let kind = kinds[row.type], let date = parseDate(row.occurredAt) else { return nil }
            return ResponseEvent(kind: kind, date: date, text: row.text)
        }
        return HistoryEntry(id: record.dispatchId, plan: record.plan, events: events,
                            crewUnit: record.crewUnit ?? Crew.unit)
    }

    // Backend timestamps are ISO 8601, with or without fractional seconds.
    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        // Drop the fraction and try again (e.g. six-digit microseconds).
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return plain.date(from: trimmed)
    }
}
