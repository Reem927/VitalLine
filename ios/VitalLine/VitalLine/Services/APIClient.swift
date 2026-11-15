import Foundation

enum API {
    // useMock = true runs the app on MockData with no backend.
    // Simulator: talks to the backend on this Mac (cd backend && .venv/bin/uvicorn app.main:app).
    // Phone: paste the tunnel URL below.
    static let useMock = false
    #if targetEnvironment(simulator)
    static let baseURL = URL(string: "http://localhost:8000")!
    #else
    static let baseURL = URL(string: "https://YOUR-TUNNEL-URL.trycloudflare.com")!
    #endif
    static let scenarioId = "houston-cardiac-14"

    // Where the rig starts. Fixed near the demo building so the route looks right
    // on stage; swap for the phone's GPS (CoreLocation) if you have time.
    static let crewLocation = LatLon(lat: 29.7570, lon: -95.3640)

    private static func request(elevatorOut: Bool, dispatchId: String? = nil) -> PlanRequest {
        PlanRequest(scenarioId: scenarioId, elevatorOut: elevatorOut, crewLocation: crewLocation,
                    dispatchId: dispatchId)
    }

    // MARK: Launch — POST /dispatch (the raw call; no agents)

    // `dispatchId` links every later call (plan jobs, timeline, history) to this call.
    static func fetchDispatch() async throws -> DispatchResponse {
        if useMock {
            try await Task.sleep(for: .milliseconds(400))
            return try decode(DispatchResponse.self, from: mockJSON(false))   // extra keys ignored
        }
        let data = try await post("dispatch", body: request(elevatorOut: false))
        return try decode(DispatchResponse.self, from: data)
    }

    // MARK: Agents — POST /plan/start, then poll GET /plan/{job_id}

    // Yields an update every time an agent makes progress.
    // The last update has status "done" (with the full plan) or "error".
    // `cached` only affects the mock: location/outdoor finish instantly on a re-plan.
    static func planUpdates(elevatorOut: Bool, cached: Bool,
                            dispatchId: String? = nil) -> AsyncThrowingStream<PlanJob, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    if useMock {
                        try await mockAgents(elevatorOut: elevatorOut, cached: cached, continuation)
                    } else {
                        let start = try decode(StartJobResponse.self, from: try await post(
                            "plan/start", body: request(elevatorOut: elevatorOut, dispatchId: dispatchId)))
                        while true {
                            let job = try decode(PlanJob.self, from: try await get("plan/\(start.jobId)"))
                            continuation.yield(job)
                            if job.status != "running" { break }
                            try await Task.sleep(for: .milliseconds(700))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: Timeline — the backend keeps the traceable record for History

    // kind: "en_route" | "arrived_at_building" | "entered_lobby" | "at_patient"
    // Best effort: a failed log call never blocks the crew.
    static func logEvent(dispatchId: String?, kind: String, at date: Date) async {
        guard !useMock, let dispatchId else { return }
        let body = CrewEventRequest(kind: kind, at: ISO8601DateFormatter().string(from: date))
        _ = try? await post("dispatch/\(dispatchId)/events", body: body)
    }

    // "Completed! Save to History?" Yes / No.
    static func complete(dispatchId: String?, save: Bool) async {
        guard !useMock, let dispatchId else { return }
        _ = try? await post("dispatch/\(dispatchId)/complete", body: CompleteRequest(save: save))
    }

    // MARK: Mock agents: same pattern as the real backend

    private static func mockAgents(elevatorOut: Bool, cached: Bool,
                                   _ c: AsyncThrowingStream<PlanJob, Error>.Continuation) async throws {
        let full = try decode(Plan.self, from: mockJSON(elevatorOut))
        let script = MockAgents.steps(elevatorOut: elevatorOut)
        var tasks = script.map { AgentTask(id: $0.id, title: $0.title, status: "pending", detail: nil) }
        var building: Building?
        var outdoor: Outdoor?

        func emit(_ status: String, _ plan: Plan? = nil) {
            c.yield(PlanJob(jobId: "mock", status: status, tasks: tasks,
                            building: building, outdoor: outdoor, plan: plan, error: nil))
        }

        emit("running")
        for i in tasks.indices {
            let step = script[i]
            tasks[i] = AgentTask(id: step.id, title: step.title, status: "running", detail: nil)
            emit("running")
            if !(cached && step.cached) {
                try await Task.sleep(for: .milliseconds(Int.random(in: 700...1300)))
            }
            tasks[i] = AgentTask(id: step.id, title: step.title, status: "done", detail: step.detail)
            if step.id == "location" { building = full.building }
            if step.id == "outdoor" { outdoor = full.outdoor }
            emit("running")
        }
        emit("done", full)
    }

    // MARK: Helpers

    private static func mockJSON(_ elevatorOut: Bool) -> Data {
        Data((elevatorOut ? MockData.elevatorOutJSON : MockData.stretcherJSON).utf8)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    private static func post<B: Encodable>(_ path: String, body: B) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    private static func get(_ path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 30
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
