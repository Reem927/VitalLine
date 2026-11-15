import Foundation
import Observation

// Shared state for every screen.
//   load()           -> app launch: the raw dispatch call (no agents)
//   startResponse()  -> "Start Response": all six agents run in one job.
//                       building/outdoor fill in early (Route Preview),
//                       plan fills in when every agent is done (Indoor Plan)
//   replan()         -> elevator toggle: same job again with the new setting
@MainActor
@Observable
final class PlanStore {
    var dispatch: DispatchInfo?
    var dispatchId: String?        // backend id; every log and plan job is filed under it
    var building: Building?
    var outdoor: Outdoor?
    var plan: Plan?
    var tasks: [AgentTask] = []
    var isLoading = false
    var isPlanning = false
    var errorMessage: String?
    var elevatorOut = false

    // Timeline of the current response, saved to History on completion.
    var events: [ResponseEvent] = []
    private var dispatchReceivedAt: Date?

    // True once every agent has finished successfully.
    var agentsDone: Bool {
        !isPlanning && plan != nil && !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await API.fetchDispatch()
            dispatch = response.dispatch
            dispatchId = response.dispatchId
            dispatchReceivedAt = .now
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // A new response: clear the previous one's results, then run every agent.
    func startResponse() async {
        events = [
            ResponseEvent(kind: .dispatchReceived, date: dispatchReceivedAt ?? .now, text: "Dispatch received"),
        ]
        log(.enRoute, "Acknowledged / En route")
        building = nil
        outdoor = nil
        plan = nil
        await runAgents(cached: false)
    }

    // Same response, new setting: keep showing the old plan until the new one lands.
    func replan() async {
        if events.contains(where: { $0.kind == .enRoute }) {
            log(.routeUpdated, elevatorOut ? "Route updated: elevator unavailable, stairs used"
                                           : "Route updated: elevator back in service")
        }
        await runAgents(cached: true)
    }

    // MARK: Timeline marks (each recorded once per response)

    func markArrivedAtBuilding() { logOnce(.arrivedAtBuilding, "Arrived at building") }
    func markEnteredLobby()      { logOnce(.enteredLobby, "Entered lobby") }
    func markAtPatient()         { logOnce(.atPatient, "At patient") }

    // "Completed! Save to History?" — the backend closes the call and stores the answer.
    func complete(save: Bool) {
        let id = dispatchId
        Task { await API.complete(dispatchId: id, save: save) }
    }

    private func log(_ kind: ResponseEvent.Kind, _ text: String) {
        let event = ResponseEvent(kind: kind, date: .now, text: text)
        events.append(event)
        // dispatchReceived and routeUpdated are logged by the backend itself.
        if let wire = kind.wireName {
            let id = dispatchId
            Task { await API.logEvent(dispatchId: id, kind: wire, at: event.date) }
        }
    }

    private func logOnce(_ kind: ResponseEvent.Kind, _ text: String) {
        guard !events.contains(where: { $0.kind == kind }) else { return }
        log(kind, text)
    }

    private func runAgents(cached: Bool) async {
        isPlanning = true
        errorMessage = nil
        tasks = []
        do {
            for try await job in API.planUpdates(elevatorOut: elevatorOut, cached: cached,
                                                    dispatchId: dispatchId) {
                tasks = job.tasks
                if let b = job.building { building = b }
                if let o = job.outdoor { outdoor = o }
                if let final = job.plan { plan = final }
                if job.status == "error" {
                    // e.g. Wolfram found a mismatch: the plan is blocked, per the build plan
                    errorMessage = job.error ?? "Planning failed"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPlanning = false
    }
}
