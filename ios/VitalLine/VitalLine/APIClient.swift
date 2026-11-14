import Foundation

enum API {
    // 1. While the backend isn't ready, leave useMock = true. The app runs on MockData.
    // 2. When the backend is up, paste its tunnel URL here and set useMock = false.
    static let useMock = true
    static let baseURL = URL(string: "https://YOUR-TUNNEL-URL.trycloudflare.com")!
    static let scenarioId = "houston-cardiac-14"

    static func fetchPlan(elevatorOut: Bool) async throws -> Plan {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if useMock {
            try await Task.sleep(for: .milliseconds(400))   // feels like a network call
            let json = elevatorOut ? MockData.elevatorOutJSON : MockData.stretcherJSON
            return try decoder.decode(Plan.self, from: Data(json.utf8))
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        var request = URLRequest(url: baseURL.appendingPathComponent("plan"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60   // the agent can be slow
        request.httpBody = try encoder.encode(
            PlanRequest(scenarioId: scenarioId, elevatorOut: elevatorOut)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(Plan.self, from: data)
    }
}
