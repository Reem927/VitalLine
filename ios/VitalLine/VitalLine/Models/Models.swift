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

// "Floor 2, Unit 203" for numbered units, "Floor 2, upper landing" for named places.
func placeText(floor: Int, unit: String) -> String {
    unit.first?.isNumber == true ? "Floor \(floor), Unit \(unit)" : "Floor \(floor), \(unit)"
}

struct DispatchInfo: Codable {
    let address: String
    let floor: Int
    let unit: String
    let complaint: String
    let equipment: String          // "stretcher" | "stair_chair" | "bariatric"
    let priority: String?          // "High" | "Medium" | "Low"
    let etaMinutes: Int?           // estimate sent with the call (CAD), before routing runs
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
    let maneuvers: [Maneuver]?     // turn-by-turn from Valhalla; nil in mock data
    let routeNote: String?         // which driving rules the route used (emergency or ordinary)
    let aerial: Aerial?            // Vexcel aerial view with where to stop, if available
}

// Aerial image of the building. Marker positions are fractions of the image (0...1).
struct Aerial: Codable {
    let imageUrl: String
    let widthM: Int
    let markers: [AerialMarker]
    let note: String?
}

struct AerialMarker: Codable {
    let kind: String               // "stop" | "building"
    let label: String
    let fx: Double
    let fy: Double
}

// One turn instruction. shapeIndex is where it begins in `route`.
struct Maneuver: Codable {
    let text: String
    let shapeIndex: Int
    let lat: Double
    let lon: Double
    let km: Double?
    let seconds: Double?
    let type: Int?
}

// A point in metres. Plan frame: x right, y up, z = floor-plan y (grows downward).
// AR frame (arRoute): origin at the first point, Y up, first leg along -Z.
struct Point3: Codable {
    let x: Double
    let y: Double
    let z: Double
}

// One leg of the route, marked real (from scan data) or modeled/estimated.
struct Leg: Codable, Identifiable {
    let id: Int
    let kind: String               // "walk" | "elevator" | "stairs"
    let text: String
    let real: Bool
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
    let wallHeightM: Double?       // scanned ceiling height, for the 3D view
    let path3d: [Point3]?          // path in the plan frame, for the 3D view
    let arRoute: [Point3]?         // path in the AR frame, for AR navigation
    let legs: [Leg]?
    let meshUrl: String?           // backend path of the real scan mesh manifest, if any
    let nav: Nav?                  // walkable graph for live AR re-routing, if the scan has one
}

// Walkable graph of the scanned space, in the plan frame (metres; x, y up, z).
struct Nav: Codable {
    let nodes: [Point3]
    let edges: [[Int]]             // pairs of node indices
    let start: Int                 // suggested starting point
    let goal: Int                  // the patient's point
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
    let verifiedBy: String?        // "wolfram" | "local_exact_arithmetic"; nil in mock data
}

// What POST /dispatch returns: the raw call from 911/CAD. No agents have run yet.
struct DispatchResponse: Codable {
    let dispatch: DispatchInfo
    let dispatchId: String?        // backend id for this call; nil in mock data
}

// What the app sends to POST /dispatch and POST /plan/start.
struct PlanRequest: Codable {
    let scenarioId: String
    let elevatorOut: Bool
    let crewLocation: LatLon?      // where the rig is; outdoor-route starts here
    var dispatchId: String? = nil  // links a plan job to the call from POST /dispatch
}

// POST /dispatch/{id}/events and /complete
struct CrewEventRequest: Codable {
    let kind: String
    let at: String                 // ISO 8601
}

struct CompleteRequest: Codable {
    let save: Bool
}
