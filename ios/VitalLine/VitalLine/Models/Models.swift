import Foundation
import CoreLocation

// These structs mirror the JSON the backend sends from POST /plan.
// The decoder converts snake_case keys (elevator_ok) to camelCase (elevatorOk),
// so the backend can stay Pythonic and the app can stay Swifty.

struct Plan: Codable {
    let dispatch: DispatchInfo
    let building: Building
    let outdoor: Outdoor
    let access: [AccessNote]
    let indoor: Indoor
    let steps: [Step]
    let time: TimeRange
    let verification: Verification
    let brief: [String]
}

struct DispatchInfo: Codable {
    let address: String
    let floor: Int
    let unit: String
    let complaint: String
    let equipment: String          // "stretcher" | "stair_chair" | "bariatric"
    let priority: String?          // "High" | "Medium" | "Low"
}

struct Building: Codable {
    let name: String
    let floors: Int
    let type: String
    let source: String             // e.g. "CoStar" or "synthetic"
}

struct LatLon: Codable {
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct Flag: Codable, Identifiable {
    let id: String
    let kind: String               // "road_work" | "hazard" | "weather" | anything else
    let text: String
    let source: String
}

struct Outdoor: Codable {
    let route: [LatLon]
    let staging: LatLon
    let entrance: LatLon
    let flags: [Flag]
    let etaMinutes: Int?           // drive time rig -> entrance
    let distanceKm: Double?
}

struct AccessNote: Codable, Identifiable {
    let id: String
    let text: String
    let confidence: String         // "high" | "medium" | "low" | "unknown"
    let synthetic: Bool
}

// Floor-plan coordinates are in meters, origin at the top-left, y grows downward.
struct PlanPoint: Codable {
    let x: Double
    let y: Double
}

struct Room: Codable, Identifiable {
    let id: String
    let name: String
    let polygon: [PlanPoint]
}

struct Door: Codable, Identifiable {
    let id: String
    let at: PlanPoint
    let widthIn: Double
    let passable: Bool
}

struct Indoor: Codable {
    let floor: Int
    let widthM: Double
    let heightM: Double
    let rooms: [Room]
    let doors: [Door]
    let path: [PlanPoint]
    let mode: String               // "stretcher" | "stair_chair"
    let elevatorOk: Bool
    let floorPlanImageUrl: String? // optional: CoStar/Matterport floor plan image
}

struct Step: Codable, Identifiable {
    let id: Int
    let text: String
    let secondsMin: Int
    let secondsMax: Int
}

struct TimeRange: Codable {
    let minSeconds: Int
    let maxSeconds: Int
}

struct Verification: Codable {
    let verified: Bool
    let expression: String
    let result: String
}

// What the app sends to POST /plan.
struct PlanRequest: Codable {
    let scenarioId: String
    let elevatorOut: Bool
}
