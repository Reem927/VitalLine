import Foundation
import Observation

// The single source of truth for the screen. Views read from it;
// changing elevatorOut and calling load() refreshes everything.
@MainActor
@Observable
final class PlanStore {
    var plan: Plan?
    var isLoading = false
    var errorMessage: String?
    var elevatorOut = false

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
}
