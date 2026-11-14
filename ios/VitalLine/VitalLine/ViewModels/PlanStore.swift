import Foundation
import Observation

// Shared state for every screen.
//   load()       -> quick plan at launch (dispatch + outdoor route)
//   runAgents()  -> agents work step by step; `tasks` updates live,
//                   `plan` is replaced with the final plan when they finish
@MainActor
@Observable
final class PlanStore {
    var plan: Plan?
    var tasks: [AgentTask] = []
    var isLoading = false
    var isPlanning = false
    var errorMessage: String?
    var elevatorOut = false

    // True once every agent step has finished.
    var agentsDone: Bool {
        !isPlanning && !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            plan = try await API.fetchPlan(elevatorOut: elevatorOut)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func runAgents() async {
        isPlanning = true
        errorMessage = nil
        tasks = []
        do {
            for try await job in API.planUpdates(elevatorOut: elevatorOut) {
                tasks = job.tasks
                if let final = job.plan { plan = final }
                if job.status == "error" {
                    errorMessage = job.error ?? "Planning failed"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPlanning = false
    }
}
