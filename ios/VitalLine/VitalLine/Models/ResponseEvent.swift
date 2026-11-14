import Foundation

// One timestamped line in a response's timeline (History detail screen).
// PlanStore records these as the crew moves through the app.
struct ResponseEvent: Identifiable {
    enum Kind {
        case dispatchReceived   // dispatch loaded on the Dispatch screen
        case enRoute            // "Start Response"
        case arrivedAtBuilding  // "View Indoor Plan" (or LocationManager arrival)
        case enteredLobby       // optional: call store.markEnteredLobby()
        case routeUpdated       // elevator toggle during a response
        case atPatient          // "Arrived at Patient"
    }

    let id = UUID()
    let kind: Kind
    let date: Date
    let text: String

    var isWarning: Bool { kind == .routeUpdated }
}
