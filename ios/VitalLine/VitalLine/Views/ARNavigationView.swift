import SwiftUI
import ARKit
import RealityKit
import UIKit
import simd

// AR navigation along the recommended plan.
//
// The backend sends a walkable graph of the scanned space (indoor.nav): points in metres
// (x, y up, z), links between them, the patient's point and a suggested start. This screen:
//   1. lets the crew pick the scan point nearest to where they stand (not only the entrance),
//   2. lines AR up there: stand on that point, face the first arrow on the map, then start,
//   3. tracks the phone as it moves and keeps re-routing along the shortest way to the patient.
//
// There is no automatic indoor positioning: GPS is unreliable indoors and the scan has no
// compass alignment, so the start point is chosen by hand. Tracking can drift; realign if needed.

// MARK: - Graph

struct NavGraph {
    let points: [SIMD3<Float>]
    let goal: Int
    let suggestedStart: Int
    private let neighbors: [[(Int, Float)]]
    private(set) var costToGoal: [Float]      // walking distance from each point to the goal
    private(set) var next: [Int]              // next point on the shortest way to the goal

    init?(_ nav: Nav?) {
        guard let nav, nav.nodes.count >= 2, nav.nodes.indices.contains(nav.goal) else { return nil }
        points = nav.nodes.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
        goal = nav.goal
        suggestedStart = nav.nodes.indices.contains(nav.start) ? nav.start : 0
        var adjacency = Array(repeating: [(Int, Float)](), count: points.count)
        for e in nav.edges where e.count == 2 && points.indices.contains(e[0]) && points.indices.contains(e[1]) {
            let d = simd_distance(points[e[0]], points[e[1]])
            adjacency[e[0]].append((e[1], d))
            adjacency[e[1]].append((e[0], d))
        }
        neighbors = adjacency

        // Dijkstra outward from the goal: one pass gives the shortest way from every point.
        var cost = Array(repeating: Float.infinity, count: points.count)
        var step = Array(repeating: -1, count: points.count)
        var open = Set(points.indices)
        cost[goal] = 0
        while let u = open.min(by: { cost[$0] < cost[$1] }), cost[u].isFinite {
            open.remove(u)
            for (v, d) in adjacency[u] where cost[u] + d < cost[v] {
                cost[v] = cost[u] + d
                step[v] = u
            }
        }
        costToGoal = cost
        next = step
    }

    // A straight chain, used when the plan has a path but no graph.
    static func chain(_ route: [Point3]?) -> NavGraph? {
        guard let route, route.count >= 2 else { return nil }
        let edges = (0..<(route.count - 1)).map { [$0, $0 + 1] }
        return NavGraph(Nav(nodes: route, edges: edges, start: 0, goal: route.count - 1))
    }

    func path(from start: Int) -> [Int] {
        var out = [start], current = start
        while current != goal, next[current] >= 0, out.count <= points.count {
            current = next[current]
            out.append(current)
        }
        return out
    }

    // Best point to head for from a position: near the user and on a short way to the goal.
    func entry(near p: SIMD3<Float>) -> Int? {
        let reachable = points.indices.filter { costToGoal[$0].isFinite && abs(points[$0].y - p.y) < 1.6 }
        let close = reachable.filter { simd_distance(points[$0], p) < 4.5 }
        let pool = close.isEmpty ? reachable : close
        return pool.min { simd_distance(points[$0], p) + costToGoal[$0] < simd_distance(points[$1], p) + costToGoal[$1] }
    }
}

// MARK: - Screen

struct ARNavigationView: View {
    @Environment(PlanStore.self) private var store
    @State private var start: Int?
    @State private var running = false
    @State private var startVersion = 0
    @State private var status = ARStatus()

    private var graph: NavGraph? {
        let indoor = store.plan?.indoor
        // The plan's own route, entrance to patient, placed once and kept fixed.
        return NavGraph.chain(indoor?.path3d) ?? NavGraph(indoor?.nav)
    }

    var body: some View {
        ZStack {
            if let graph {
                ARRouteView(graph: graph, start: start ?? graph.suggestedStart,
                            running: running, startVersion: startVersion, status: $status)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                Spacer()
                if let graph { panel(graph) } else { noRoute }
            }
        }
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.north.line.fill").foregroundStyle(.cyan)
            Text("VITALLINE AR").font(.headline)
            Spacer()
            if running {
                Text(status.arrived ? "ARRIVED" : String(format: "%.0f m to patient", status.remaining))
                    .font(.caption.bold()).foregroundStyle(.cyan)
            }
        }
        .padding()
        .background(.black.opacity(0.78))
    }

    private var noRoute: some View {
        Text("This plan has no AR route.")
            .padding().background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18)).padding()
    }

    private func panel(_ graph: NavGraph) -> some View {
        let chosen = start ?? graph.suggestedStart
        return VStack(spacing: 12) {
            if running {
                Text(status.arrived ? "You have reached the patient's location"
                                    : (status.rerouted ? "Route updated from where you are" : "Follow the chevrons"))
                    .font(.headline)
                Text("Shortest route from the entrance, fixed in place. If the arrows drift, go back to the entrance and tap Realign.")
                    .font(.caption).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Realign") { running = false }
                        .buttonStyle(.bordered).tint(.white)
                    Button("Stop") { running = false; start = nil }
                        .buttonStyle(.bordered).tint(.white)
                }
            } else {
                Text("Start at the building entrance").font(.headline)
                Text("Stand at the entrance (green) and face into the building along the cyan line, then start. The arrows lead to the patient (red).")
                    .font(.caption).multilineTextAlignment(.center)
                StartPicker(graph: graph, rooms: store.plan?.indoor.rooms ?? [], chosen: chosen) { _ in }
                    .frame(height: 190)
                Button {
                    startVersion += 1
                    running = true
                } label: {
                    Label("Start AR Route", systemImage: "location.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
            }
            Text("Prototype only. Not for real emergency navigation.")
                .font(.caption2).foregroundStyle(.gray)
        }
        .padding()
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
        .padding()
    }
}

struct ARStatus: Equatable {
    var remaining: Float = 0
    var arrived = false
    var rerouted = false
}

// Top-down map of the scan points: tap the one nearest to you.
private struct StartPicker: View {
    let graph: NavGraph
    let rooms: [Room]
    let chosen: Int
    let pick: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let level = graph.points[chosen].y
            let visible = graph.points.indices.filter { abs(graph.points[$0].y - level) < 1.2 || $0 == graph.goal }
            let xs = visible.map { graph.points[$0].x }, zs = visible.map { graph.points[$0].z }
            let minX = (xs.min() ?? 0) - 1, maxX = (xs.max() ?? 1) + 1
            let minZ = (zs.min() ?? 0) - 1, maxZ = (zs.max() ?? 1) + 1
            let scale = min(geo.size.width / CGFloat(maxX - minX), geo.size.height / CGFloat(maxZ - minZ))
            let place: (Float, Float) -> CGPoint = { x, z in
                CGPoint(x: CGFloat(x - minX) * scale, y: CGFloat(z - minZ) * scale)
            }
            let route = graph.path(from: chosen)

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for room in rooms where room.polygon.count >= 3 {
                        var outline = Path()
                        outline.move(to: place(Float(room.polygon[0].x), Float(room.polygon[0].y)))
                        for p in room.polygon.dropFirst() { outline.addLine(to: place(Float(p.x), Float(p.y))) }
                        outline.closeSubpath()
                        context.stroke(outline, with: .color(.white.opacity(0.18)), lineWidth: 1)
                    }
                    var line = Path()
                    for (i, n) in route.enumerated() {
                        let p = place(graph.points[n].x, graph.points[n].z)
                        if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                    }
                    context.stroke(line, with: .color(.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    for n in visible {
                        let p = place(graph.points[n].x, graph.points[n].z)
                        guard n == chosen || n == graph.goal else { continue }   // start and patient only
                        let r: CGFloat = 7
                        let color: Color = n == graph.goal ? .red : .green
                        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Camera and route renderer

private struct ARRouteView: UIViewRepresentable {
    let graph: NavGraph
    let start: Int
    let running: Bool
    let startVersion: Int
    @Binding var status: ARStatus

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        view.session.run(configuration)
        view.session.delegate = context.coordinator
        context.coordinator.arView = view
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let c = context.coordinator
        c.report = { new in if new != status { status = new } }
        if !running {
            c.stop()
        } else if c.lastStartVersion != startVersion {
            c.lastStartVersion = startVersion
            c.begin(graph: graph, start: start)
        }
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        var lastStartVersion = 0
        var report: (ARStatus) -> Void = { _ in }

        private var graph: NavGraph?
        private var anchor: AnchorEntity?
        private var content: Entity?
        private var rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        private var origin = SIMD3<Float>(repeating: 0)
        private var entry: Int?
        private var initialEntry: Int?
        private var lastUpdate: TimeInterval = 0
        private var cameraHeight: Float = 1.25       // phone height above the floor; measured when possible

        func stop() {
            if let anchor, let arView { arView.scene.removeAnchor(anchor) }
            anchor = nil; content = nil; graph = nil; entry = nil
        }

        // Line AR up: the phone stands on the chosen point, facing along the first leg.
        func begin(graph: NavGraph, start: Int) {
            guard let arView else { return }
            stop()
            let camera = arView.cameraTransform
            let forward = SIMD3<Float>(-camera.matrix.columns.2.x, 0, -camera.matrix.columns.2.z)
            guard simd_length(forward) > 0.001 else { return }
            let heading = simd_normalize(forward)
            let cameraYaw = atan2(-heading.x, -heading.z)

            // Measure how high the phone is above the real floor, when ARKit can see the floor.
            let down = ARRaycastQuery(origin: camera.translation, direction: SIMD3<Float>(0, -1, 0),
                                      allowing: .estimatedPlane, alignment: .horizontal)
            if let hit = arView.session.raycast(down).first {
                let height = camera.translation.y - hit.worldTransform.columns.3.y
                if height > 1.0 && height < 1.7 { cameraHeight = height }
            }

            let route = graph.path(from: start)
            var leg = SIMD3<Float>(0, 0, -1)
            if route.count >= 2 {
                let d = graph.points[route[1]] - graph.points[route[0]]
                if simd_length(SIMD3<Float>(d.x, 0, d.z)) > 0.05 { leg = simd_normalize(SIMD3<Float>(d.x, 0, d.z)) }
            }
            let legYaw = atan2(-leg.x, -leg.z)
            rotation = simd_quatf(angle: cameraYaw - legYaw, axis: SIMD3<Float>(0, 1, 0))
            origin = camera.translation - rotation.act(graph.points[start]) - SIMD3<Float>(0, cameraHeight, 0)

            let anchor = AnchorEntity(world: origin)
            let content = Entity()
            content.orientation = rotation
            anchor.addChild(content)
            arView.scene.addAnchor(anchor)
            self.anchor = anchor
            self.content = content
            self.graph = graph
            self.initialEntry = start
            draw(from: start, user: graph.points[start])
        }

        // Twice a second: where is the phone in the scan, and what is the shortest way from there?
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let graph, frame.timestamp - lastUpdate > 0.5 else { return }
            lastUpdate = frame.timestamp
            let world = SIMD3<Float>(frame.camera.transform.columns.3.x,
                                     frame.camera.transform.columns.3.y,
                                     frame.camera.transform.columns.3.z)
            var user = rotation.inverse.act(world - origin)
            user.y -= cameraHeight                              // floor height under the phone
            guard let best = graph.entry(near: user) else { return }
            // The route stays where it was placed at the start. Redrawing it from the
            // tracked position made the arrows jump whenever tracking drifted.
            snapArrows(near: world)

            let goal = graph.points[graph.goal]
            let flat = simd_distance(SIMD2<Float>(user.x, user.z), SIMD2<Float>(goal.x, goal.z))
            let arrived = flat < 1.5 && abs(user.y - goal.y) < 1.5
            let remaining = simd_distance(user, graph.points[best]) + graph.costToGoal[best]
            let status = ARStatus(remaining: remaining, arrived: arrived, rerouted: false)
            DispatchQueue.main.async { self.report(status) }
        }

        private func draw(from entry: Int, user: SIMD3<Float>) {
            guard let graph, let content else { return }
            self.entry = entry
            content.children.removeAll()
            var points = graph.path(from: entry).map { graph.points[$0] }
            if simd_distance(user, points[0]) > 0.7 { points.insert(user, at: 0) }   // lead the user onto the route
            for index in 0..<(points.count - 1) {
                let a = points[index], b = points[index + 1]
                let segment = b - a
                let distance = simd_length(segment)
                if distance < 0.05 { continue }
                let flat = SIMD3<Float>(segment.x, 0, segment.z)
                let direction = simd_length(flat) > 0.01 ? simd_normalize(flat) : SIMD3<Float>(0, 0, -1)
                let count = max(1, Int(ceil(distance / 0.9)))
                for step in 0..<count {
                    let t = (Float(step) + 0.5) / Float(count)
                    let arrow = makeArrow()
                    arrow.position = a + segment * t + SIMD3<Float>(0, 0.025, 0)
                    arrow.orientation = simd_quatf(angle: atan2(-direction.x, -direction.z), axis: SIMD3<Float>(0, 1, 0))
                    content.addChild(arrow)
                }
            }
            // Patient marker at the goal.
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.18), materials: [UnlitMaterial(color: .systemRed)])
            marker.position = graph.points[graph.goal] + SIMD3<Float>(0, 1.0, 0)
            content.addChild(marker)
        }

        // Drop nearby arrows onto the surface ARKit sees under them (floor, landing, stair
        // tread), so they sit on the real ground and not at the scan's estimated height.
        private func snapArrows(near camera: SIMD3<Float>) {
            guard let arView, let content else { return }
            for arrow in content.children where arrow.name == "arrow" {
                let world = arrow.position(relativeTo: nil)
                guard simd_distance(world, camera) < 6 else { continue }
                let query = ARRaycastQuery(origin: world + SIMD3<Float>(0, 0.9, 0), direction: SIMD3<Float>(0, -1, 0),
                                           allowing: .estimatedPlane, alignment: .horizontal)
                guard let hit = arView.session.raycast(query).first else { continue }
                let y = hit.worldTransform.columns.3.y
                // Small corrections only, onto flat ground: never up onto furniture.
                if abs(y - world.y) < 0.35 {
                    arrow.setPosition(SIMD3<Float>(world.x, y + 0.025, world.z), relativeTo: nil)
                }
            }
        }

        // Two flat cyan bars form a forward-pointing chevron on the floor (local forward is -Z).
        private func makeArrow() -> Entity {
            let arrow = Entity()
            arrow.name = "arrow"
            let material = UnlitMaterial(color: UIColor.cyan)
            for side in [Float(-1), 1] {
                let bar = ModelEntity(mesh: .generateBox(width: 0.105, height: 0.012, depth: 0.48), materials: [material])
                bar.position = SIMD3<Float>(0.16 * side, 0, 0)
                bar.orientation = simd_quatf(angle: .pi / 4 * side, axis: SIMD3<Float>(0, 1, 0))
                arrow.addChild(bar)
            }
            return arrow
        }
    }
}

#Preview {
    NavigationStack {
        ARNavigationView()
    }
}
