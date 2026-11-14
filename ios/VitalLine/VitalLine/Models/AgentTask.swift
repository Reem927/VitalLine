import Foundation

// One agent step shown on the "Creating Plan…" screen.
struct AgentTask: Codable, Identifiable, Equatable {
    let id: String          // "parking" | "entrance" | "vertical" | "route" | "verify"
    let title: String       // "Parking"
    let status: String      // "pending" | "running" | "done" | "failed"
    let detail: String?     // "Garage A (Level 1)", filled in when done

    var isDone: Bool { status == "done" }
    var isRunning: Bool { status == "running" }
}

// What GET /plan/{job_id} returns while the agents work.
// `plan` stays null until status == "done".
struct PlanJob: Codable {
    let jobId: String
    let status: String      // "running" | "done" | "error"
    let tasks: [AgentTask]
    let plan: Plan?
    let error: String?
}

struct StartJobResponse: Codable {
    let jobId: String
}

// Synthetic agent results used while API.useMock == true.
enum MockAgents {
    static func tasks(elevatorOut: Bool) -> [(id: String, title: String, detail: String)] {
        [
            ("parking", "Parking", "Garage A (Level 1)"),
            ("entrance", "Closest Entrance", "Main entrance, east side"),
            ("vertical", "Elevator / Staircase",
             elevatorOut ? "Elevators out: Stair B with stair chair" : "Elevator 2 fits stretcher"),
            ("route", "Generating Floor Plan Route", "Floor 14 route to unit 1404"),
            ("verify", "Verifying with Wolfram", "Distances and times verified"),
        ]
    }
}
