import Foundation

enum API {
    // While the backend isn't ready, leave useMock = true. The app runs on MockData.
    // When the backend is up, paste its tunnel URL here and set useMock = false.
    static let useMock = true
    static let baseURL = URL(string: "https://YOUR-TUNNEL-URL.trycloudflare.com")!
    static let scenarioId = "houston-cardiac-14"

    // MARK: Quick plan (dispatch + outdoor route) — POST /plan

    static func fetchPlan(elevatorOut: Bool) async throws -> Plan {
        if useMock {
            try await Task.sleep(for: .milliseconds(400))
            return try decode(Plan.self, from: mockJSON(elevatorOut))
        }
        let data = try await post("plan", body: PlanRequest(scenarioId: scenarioId, elevatorOut: elevatorOut))
        return try decode(Plan.self, from: data)
    }

    // MARK: Agent planning — POST /plan/start, then poll GET /plan/{job_id}

    // Yields an update every time the agents make progress.
    // The last update has status "done" and a full plan.
    static func planUpdates(elevatorOut: Bool) -> AsyncThrowingStream<PlanJob, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    if useMock {
                        try await mockAgents(elevatorOut: elevatorOut, continuation)
                    } else {
                        let start = try decode(StartJobResponse.self, from: try await post(
                            "plan/start",
                            body: PlanRequest(scenarioId: scenarioId, elevatorOut: elevatorOut)))
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

    // MARK: Mock agents: tasks finish one at a time, like the real backend

    private static func mockAgents(elevatorOut: Bool,
                                   _ c: AsyncThrowingStream<PlanJob, Error>.Continuation) async throws {
        let script = MockAgents.tasks(elevatorOut: elevatorOut)
        var tasks = script.map { AgentTask(id: $0.id, title: $0.title, status: "pending", detail: nil) }
        func emit(_ status: String, _ plan: Plan? = nil) {
            c.yield(PlanJob(jobId: "mock", status: status, tasks: tasks, plan: plan, error: nil))
        }

        emit("running")
        for i in tasks.indices {
            tasks[i] = AgentTask(id: tasks[i].id, title: tasks[i].title, status: "running", detail: nil)
            emit("running")
            try await Task.sleep(for: .milliseconds(Int.random(in: 700...1300)))
            tasks[i] = AgentTask(id: tasks[i].id, title: tasks[i].title, status: "done", detail: script[i].detail)
            emit("running")
        }
        emit("done", try decode(Plan.self, from: mockJSON(elevatorOut)))
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
