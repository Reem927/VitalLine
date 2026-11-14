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
    var building: Building?
    var outdoor: Outdoor?
    var plan: Plan?
    var tasks: [AgentTask] = []
    var isLoading = false
    var isPlanning = false
    var errorMessage: String?
    var elevatorOut = false

    // True once every agent has finished successfully.
    var agentsDone: Bool {
        !isPlanning && plan != nil && !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            dispatch = try await API.fetchDispatch()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // A new response: clear the previous one's results, then run every agent.
    func startResponse() async {
        building = nil
        outdoor = nil
        plan = nil
        await runAgents(cached: false)
    }

    // Same response, new setting: keep showing the old plan until the new one lands.
    func replan() async {
        await runAgents(cached: true)
    }

    private func runAgents(cached: Bool) async {
        isPlanning = true
        errorMessage = nil
        tasks = []
        do {
            for try await job in API.planUpdates(elevatorOut: elevatorOut, cached: cached) {
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
