import Foundation

// One agent shown on the "Creating Plan…" screen.
// ids match the six subagents in the build plan:
//   location  -> location-resolver (geocode + CoStar property)
//   outdoor   -> outdoor-route (Valhalla, TxDOT, 311, NWS)
//   access    -> access-checker (Vexcel, building profile)
//   indoor    -> indoor-planner (Matterport graph, equipment fit)
//   verify    -> verifier (Wolfram)
//   brief     -> briefer
struct AgentTask: Codable, Identifiable, Equatable {
    let id: String
    let title: String       // "Access check"
    let status: String      // "pending" | "running" | "done" | "failed"
    let detail: String?     // "Parking: Garage A · Entrance: east side"

    var isDone: Bool { status == "done" }
    var isRunning: Bool { status == "running" }
    var isFailed: Bool { status == "failed" }
}

// What GET /plan/{job_id} returns while the agents work.
// Partial results appear as soon as their agent finishes:
//   building -> after location, outdoor -> after outdoor (Route Preview needs these)
//   plan     -> only when status == "done"
struct PlanJob: Codable {
    let jobId: String
    let status: String      // "running" | "done" | "error"
    let tasks: [AgentTask]
    let building: Building?
    let outdoor: Outdoor?
    let plan: Plan?
    let error: String?
}

struct StartJobResponse: Codable {
    let jobId: String
}

// Synthetic agent results used while API.useMock == true.
// On a re-plan (elevator toggle) the `cached` agents finish instantly,
// like a backend that caches location and outdoor results.
enum MockAgents {
    struct Step {
        let id: String
        let title: String
        let detail: String
        let cached: Bool
    }

    static func steps(elevatorOut: Bool) -> [Step] {
        [
            Step(id: "location", title: "Building lookup",
                 detail: "CoStar: Demo Tower, 22 floors, residential", cached: true),
            Step(id: "outdoor", title: "Outdoor route",
                 detail: "8 min via Valhalla · 2 flags (TxDOT, 311)", cached: true),
            Step(id: "access", title: "Access check",
                 detail: "Parking: Garage A · Entrance: east side", cached: false),
            Step(id: "indoor", title: "Indoor route",
                 detail: elevatorOut ? "Elevators out: Stair B with stair chair"
                                     : "Elevator 2 fits stretcher · 35 m to unit 1404",
                 cached: false),
            Step(id: "verify", title: "Wolfram verification",
                 detail: "Distances and times verified", cached: false),
            Step(id: "brief", title: "Crew brief",
                 detail: "5-line brief ready", cached: false),
        ]
    }
}
