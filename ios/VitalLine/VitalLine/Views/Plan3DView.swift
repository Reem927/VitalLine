import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

// Recommended Plan in 3D. Shows the real Matterport scan mesh when the backend has one
// (indoor.meshUrl), with the crew path, door markers and a marker walking the route drawn
// inside it. Until the mesh has downloaded, or if there is none, it shows walls raised from
// the scanned room outlines instead.
// Coordinates are metres: x = floor-plan x, z = floor-plan y, y up. Drag to orbit, pinch to zoom.
struct Plan3DView: View {
    let indoor: Indoor
    @State private var scene: SCNScene
    @State private var camera: SCNNode
    @State private var meshState = MeshState.none
    @State private var walking = false     // first-person walkthrough along the route
    @State private var stage: String?      // which part of the walkthrough is playing
    @State private var lobbyReady = false  // the entrance scan has loaded

    enum MeshState: Equatable { case none, loading, shown, failed }

    init(indoor: Indoor) {
        self.indoor = indoor
        // The camera lives inside the scene so it keeps its place when the mesh arrives.
        let scene = PlanScene.make(indoor)
        let camera = PlanScene.camera(indoor)
        scene.rootNode.addChildNode(camera)
        _scene = State(initialValue: scene)
        _camera = State(initialValue: camera)
    }

    // Use as .id(...) so the view rebuilds when the plan changes (elevator toggle).
    static func key(_ indoor: Indoor) -> String {
        "\(indoor.mode)-\(indoor.elevatorOk)-\(indoor.path.count)-\(indoor.rooms.count)-\(indoor.meshUrl ?? "")"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneView(scene: scene, pointOfView: camera,
                      options: [.allowsCameraControl, .autoenablesDefaultLighting])
                .background(Color.midnight)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if let badge {
                Text(walking ? "WALKTHROUGH · SIMULATED CAMERA IN THE REAL SCAN" : badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
            }

            // First-person preview for when the crew is not on site: the camera walks the
            // route at eye height inside the scan. It is a simulation, not live AR.
            Button {
                walking.toggle()
                if walking {
                    let gap = (indoor.legs ?? []).filter { !$0.real }.map(\.text).joined(separator: "\n")
                    PlanScene.startWalk(camera, indoor, includeLobby: lobbyReady,
                                        gapText: gap.isEmpty ? "Elevator and corridor: not scanned" : gap) { stage = $0 }
                } else {
                    stage = nil
                    PlanScene.resetCamera(camera, indoor)
                }
            } label: {
                Label(walking ? "Overview" : "Walk the route", systemImage: walking ? "cube" : "figure.walk")
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.brandPrimary, in: Capsule())
                    .foregroundStyle(Color.midnight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)

            if walking, let stage {
                Text(stage)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 10).padding(.bottom, 10).padding(.trailing, 150)
            }
        }
        .task { await loadMesh() }
    }

    private var badge: String? {
        switch meshState {
        case .none: return nil
        case .loading: return "Loading real scan…"
        case .shown: return "REAL SCAN · MATTERPORT"
        case .failed: return "Scan mesh unavailable · showing room outlines"
        }
    }

    private func loadMesh() async {
        guard meshState == .none, let path = indoor.meshUrl, !API.useMock else { return }
        meshState = .loading
        do {
            let node = try await ScanMesh.load(manifestPath: path)
            PlanScene.showMesh(node, in: scene)
            meshState = .shown
            // The entrance scan is a separate scan: load it for the walkthrough's first part.
            if let lobby = indoor.lobbyWalk, let entrance = try? await ScanMesh.load(manifestPath: lobby.meshUrl) {
                PlanScene.addLobby(entrance, path: lobby.path3d, in: scene)
                lobbyReady = true
            }
        } catch {
            meshState = .failed
        }
    }
}

// Downloads the converted scan mesh once and keeps it in the app's cache folder.
enum ScanMesh {
    struct Manifest: Decodable {
        let files: [String]
        let textured: Bool
        let version: Int?
    }

    // Each scan is loaded once and shared: every 3D view gets a light copy that points at
    // the same geometry and textures, instead of loading the scan again.
    @MainActor private static var loaded: [String: SCNNode] = [:]

    @MainActor
    static func load(manifestPath: String) async throws -> SCNNode {
        if let hit = loaded[manifestPath] { return hit.clone() }
        let node = try await fetch(manifestPath: manifestPath)
        loaded[manifestPath] = node
        return node.clone()
    }

    @MainActor
    static func releaseAll() { loaded.removeAll() }

    private static func fetch(manifestPath: String) async throws -> SCNNode {
        let manifestURL = API.baseURL.appendingPathComponent(manifestPath)
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 180            // the first build on the backend can take a while
        let (data, _) = try await URLSession.shared.data(for: API.authorized(request))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(Manifest.self, from: data)

        let base = manifestURL.deletingLastPathComponent()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scan-mesh")
            .appendingPathComponent("\(base.lastPathComponent)-v\(manifest.version ?? 1)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for name in manifest.files {
                let target = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: target.path) { continue }
                group.addTask {
                    let fileRequest = API.authorized(URLRequest(url: base.appendingPathComponent(name)))
                    let (tmp, response) = try await URLSession.shared.download(for: fileRequest)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: tmp, to: target)
                }
            }
            try await group.waitForAll()
        }

        let objURL = folder.appendingPathComponent("model.obj")
        let textured = manifest.textured
        return try await Task.detached(priority: .userInitiated) {
            let asset = MDLAsset(url: objURL)
            asset.loadTextures()
            let loaded = SCNScene(mdlAsset: asset)
            let node = SCNNode()
            node.name = "scanMesh"
            for child in loaded.rootNode.childNodes { node.addChildNode(child) }
            node.enumerateHierarchy { n, _ in
                for material in n.geometry?.materials ?? [] {
                    // Scan textures already carry the room's lighting, so show them as they are.
                    material.lightingModel = textured ? .constant : .lambert
                    material.isDoubleSided = false   // looking in from outside shows the rooms
                }
            }
            guard node.childNodes.contains(where: { $0.geometry != nil || !$0.childNodes.isEmpty }) else {
                throw URLError(.cannotDecodeContentData)
            }
            return node
        }.value
    }
}

enum PlanScene {
    static let wallColor = UIColor(red: 0.53, green: 0.65, blue: 0.80, alpha: 0.35)
    static let floorColor = UIColor(red: 0.09, green: 0.14, blue: 0.22, alpha: 1)
    static let pathColor = UIColor(red: 0.13, green: 0.84, blue: 0.91, alpha: 1)

    static func make(_ indoor: Indoor) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.04, green: 0.07, blue: 0.13, alpha: 1)
        let root = scene.rootNode
        let wallH = Float(indoor.wallHeightM ?? 2.6)   // visual only, never shown as a number

        // Room outlines: shown until the real scan mesh replaces them.
        let outlines = SCNNode()
        outlines.name = "outlines"
        for room in indoor.rooms where room.polygon.count >= 3 {
            outlines.addChildNode(floor(room))
            let pts = room.polygon + [room.polygon[0]]
            for (a, b) in zip(pts, pts.dropFirst()) {
                outlines.addChildNode(wall(a, b, height: wallH))
            }
        }
        root.addChildNode(outlines)

        for room in indoor.rooms where room.polygon.count >= 3 && !room.name.isEmpty {
            root.addChildNode(label(room.name, at: centroid(room.polygon), height: 0.3))
        }

        for door in indoor.doors {
            let marker = SCNNode(geometry: SCNBox(width: 0.25, height: 0.06, length: 0.25, chamferRadius: 0.03))
            marker.geometry?.firstMaterial?.diffuse.contents = door.passable ? UIColor.systemGreen : UIColor.systemRed
            marker.geometry?.firstMaterial?.emission.contents = door.passable ? UIColor.systemGreen : UIColor.systemRed
            marker.position = SCNVector3(Float(door.at.x), 0.08, Float(door.at.y))
            root.addChildNode(marker)
        }

        // The path keeps its real height changes (stairs) when the backend sends them.
        let pts = (indoor.path3d?.map { SCNVector3(Float($0.x), Float($0.y) + 0.15, Float($0.z)) })
            ?? indoor.path.map { SCNVector3(Float($0.x), 0.15, Float($0.y)) }
        if pts.count >= 2 {
            for (a, b) in zip(pts, pts.dropFirst()) { root.addChildNode(tube(a, b)) }
            root.addChildNode(sphere(at: pts.first!, color: .systemGreen, radius: 0.18))
            root.addChildNode(sphere(at: pts.last!, color: .systemRed, radius: 0.24))
            root.addChildNode(walker(along: pts))
            root.addChildNode(chevrons(along: pts))
        }

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .ambient
        light.light?.intensity = 600
        root.addChildNode(light)
        return scene
    }

    // Swap the room outlines for the real scan mesh.
    @MainActor
    static func showMesh(_ mesh: SCNNode, in scene: SCNScene) {
        scene.rootNode.childNode(withName: "outlines", recursively: false)?.isHidden = true
        scene.rootNode.childNode(withName: "scanMesh", recursively: false)?.removeFromParentNode()
        scene.rootNode.addChildNode(mesh)
    }

    private static func routePoints(_ indoor: Indoor) -> [SCNVector3] {
        (indoor.path3d?.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) })
            ?? indoor.path.map { SCNVector3(Float($0.x), 0, Float($0.y)) }
    }

    // Walk the camera along the route at eye height, looking where it is going.
    // The entrance scan sits far to the side of the unit scan: the two scans have separate
    // frames, so they are shown one after the other, never as one joined model.
    static let lobbyOffset: Float = -200

    @MainActor
    static func addLobby(_ mesh: SCNNode, path: [Point3], in scene: SCNScene) {
        scene.rootNode.childNode(withName: "lobby", recursively: false)?.removeFromParentNode()
        let group = SCNNode()
        group.name = "lobby"
        group.position = SCNVector3(lobbyOffset, 0, 0)
        mesh.name = "lobbyMesh"
        group.addChildNode(mesh)
        let pts = path.map { SCNVector3(Float($0.x), Float($0.y) + 0.15, Float($0.z)) }
        for (a, b) in zip(pts, pts.dropFirst()) { group.addChildNode(tube(a, b)) }
        group.addChildNode(chevrons(along: pts))
        scene.rootNode.addChildNode(group)
    }

    // Walk the camera at eye height: the entrance scan first (when loaded), a pause for the
    // parts with no scan, then the unit. onStage reports which part is playing.
    static func startWalk(_ camera: SCNNode, _ indoor: Indoor, includeLobby: Bool, gapText: String,
                          onStage: @escaping (String?) -> Void) {
        let eye: Float = 1.5
        let unit = routePoints(indoor).map { SCNVector3($0.x, $0.y + eye, $0.z) }
        guard unit.count >= 2 else { return }
        var lobby: [SCNVector3] = []
        if includeLobby, let walk = indoor.lobbyWalk, walk.path3d.count >= 2 {
            lobby = walk.path3d.map { SCNVector3(Float($0.x) + lobbyOffset, Float($0.y) + eye, Float($0.z)) }
        }
        camera.removeAllActions()
        camera.constraints = nil
        camera.camera?.fieldOfView = 75
        camera.camera?.zNear = 0.05
        camera.camera?.zFar = 80              // keeps the other scan out of view
        func yaw(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat { CGFloat(atan2(-(b.x - a.x), -(b.z - a.z))) }
        func say(_ text: String?) -> SCNAction { .run { _ in DispatchQueue.main.async { onStage(text) } } }
        func leg(_ pts: [SCNVector3]) -> [SCNAction] {
            var out: [SCNAction] = [.move(to: pts[0], duration: 0),
                                    .rotateTo(x: -0.12, y: yaw(pts[0], pts[1]), z: 0, duration: 0),
                                    .wait(duration: 0.8)]
            for (a, b) in zip(pts, pts.dropFirst()) {
                let d = Double(simd_length(SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z)))
                if d < 0.05 { continue }
                out.append(.rotateTo(x: -0.12, y: yaw(a, b), z: 0, duration: 0.6, usesShortestUnitArc: true))
                out.append(.move(to: b, duration: max(0.4, d / 0.8)))
            }
            return out
        }
        var actions: [SCNAction] = []
        if !lobby.isEmpty {
            actions += [say(indoor.lobbyWalk?.label)] + leg(lobby)
            actions += [say("NOT SCANNED\n" + gapText), .wait(duration: 4)]
        }
        actions += [say("Inside the unit (scanned)")] + leg(unit) + [.wait(duration: 1.5)]
        camera.runAction(.repeatForever(.sequence(actions)), forKey: "walk")
    }

    static func resetCamera(_ camera: SCNNode, _ indoor: Indoor) {
        camera.removeAllActions()
        let fresh = PlanScene.camera(indoor)
        camera.camera?.fieldOfView = fresh.camera?.fieldOfView ?? 60
        camera.camera?.zNear = 1
        camera.camera?.zFar = 500
        camera.transform = fresh.transform
    }

    // Flat chevrons on the floor along the route, like the AR arrows.
    private static func chevrons(along pts: [SCNVector3]) -> SCNNode {
        let group = SCNNode()
        for (a, b) in zip(pts, pts.dropFirst()) {
            let d = SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z)
            let length = simd_length(d)
            if length < 0.3 { continue }
            let count = max(1, Int(length / 0.8))
            for i in 0..<count {
                let t = (Float(i) + 0.5) / Float(count)
                let arrow = SCNNode()
                for side in [Float(-1), 1] {
                    let bar = SCNNode(geometry: SCNBox(width: 0.07, height: 0.01, length: 0.3, chamferRadius: 0))
                    bar.geometry?.firstMaterial?.diffuse.contents = pathColor
                    bar.geometry?.firstMaterial?.emission.contents = pathColor
                    bar.position = SCNVector3(0.1 * side, 0, 0)
                    bar.eulerAngles.y = .pi / 4 * side
                    arrow.addChildNode(bar)
                }
                arrow.position = SCNVector3(a.x + d.x * t, a.y + d.y * t - 0.1, a.z + d.z * t)
                arrow.eulerAngles.y = atan2(-d.x, -d.z)
                group.addChildNode(arrow)
            }
        }
        return group
    }

    static func camera(_ indoor: Indoor) -> SCNNode {
        let node = SCNNode()
        node.camera = SCNCamera()
        node.camera?.zFar = 500
        // Frame the route (with some room around it), not the whole building.
        let xs = indoor.path3d?.map(\.x) ?? indoor.path.map(\.x)
        let zs = indoor.path3d?.map(\.z) ?? indoor.path.map(\.y)
        let ys = indoor.path3d?.map(\.y) ?? [0]
        var cx = Float(indoor.widthM / 2), cz = Float(indoor.heightM / 2), cy: Float = 0
        var span = Float(max(indoor.widthM, indoor.heightM))
        if let x0 = xs.min(), let x1 = xs.max(), let z0 = zs.min(), let z1 = zs.max() {
            cx = Float((x0 + x1) / 2); cz = Float((z0 + z1) / 2)
            cy = Float(((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
            span = min(span, max(Float(max(x1 - x0, z1 - z0)) * 1.5, 9))
        }
        node.position = SCNVector3(cx, cy + span * 1.0, cz + span * 0.8)
        node.look(at: SCNVector3(cx, cy, cz))
        return node
    }

    // MARK: - Builders

    private static func floor(_ room: Room) -> SCNNode {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: room.polygon[0].x, y: room.polygon[0].y))
        for p in room.polygon.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.02)
        shape.firstMaterial?.diffuse.contents = floorColor
        let node = SCNNode(geometry: shape)
        node.eulerAngles.x = .pi / 2          // shape (x, y) -> scene (x, z)
        return node
    }

    private static func wall(_ a: PlanPoint, _ b: PlanPoint, height: Float) -> SCNNode {
        let dx = Float(b.x - a.x), dz = Float(b.y - a.y)
        let length = (dx * dx + dz * dz).squareRoot()
        let box = SCNBox(width: CGFloat(length), height: CGFloat(height), length: 0.06, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = wallColor
        box.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(Float(a.x) + dx / 2, height / 2, Float(a.y) + dz / 2)
        node.eulerAngles.y = atan2(-dz, dx)
        return node
    }

    // A tube between two points; handles height changes (stairs) as well as flat legs.
    private static func tube(_ a: SCNVector3, _ b: SCNVector3) -> SCNNode {
        let d = SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z)
        let length = simd_length(d)
        let cylinder = SCNCylinder(radius: 0.07, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = pathColor
        cylinder.firstMaterial?.emission.contents = pathColor
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        if length > 0.0001 {
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(d))
        }
        return node
    }

    private static func sphere(at p: SCNVector3, color: UIColor, radius: CGFloat) -> SCNNode {
        let node = SCNNode(geometry: SCNSphere(radius: radius))
        node.geometry?.firstMaterial?.diffuse.contents = color
        node.geometry?.firstMaterial?.emission.contents = color
        node.position = p
        return node
    }

    // A small marker that walks the route on a loop.
    private static func walker(along pts: [SCNVector3]) -> SCNNode {
        let node = sphere(at: pts[0], color: .white, radius: 0.12)
        var actions: [SCNAction] = []
        for (a, b) in zip(pts, pts.dropFirst()) {
            let d = Double(simd_length(SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z)))
            actions.append(.move(to: b, duration: max(0.15, d / 1.2)))
        }
        actions.append(.wait(duration: 0.6))
        actions.append(.move(to: pts[0], duration: 0))
        node.runAction(.repeatForever(.sequence(actions)))
        return node
    }

    private static func label(_ text: String, at p: PlanPoint, height: Float) -> SCNNode {
        let t = SCNText(string: text, extrusionDepth: 0)
        t.font = .systemFont(ofSize: 0.26, weight: .semibold)
        t.flatness = 0.05
        t.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.9)
        t.firstMaterial?.readsFromDepthBuffer = false     // stay readable over the scan
        let node = SCNNode(geometry: t)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
        node.position = SCNVector3(Float(p.x), height, Float(p.y))
        node.constraints = [SCNBillboardConstraint()]
        node.renderingOrder = 10
        return node
    }

    private static func centroid(_ pts: [PlanPoint]) -> PlanPoint {
        PlanPoint(x: pts.map(\.x).reduce(0, +) / Double(pts.count),
                  y: pts.map(\.y).reduce(0, +) / Double(pts.count))
    }
}
