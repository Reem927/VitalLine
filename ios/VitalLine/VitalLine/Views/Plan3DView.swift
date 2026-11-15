import SwiftUI
import SceneKit

// Recommended Plan in 3D: walls raised from the scanned room outlines, the crew path as a
// glowing tube, doors marked green (fits the equipment) or red, and a marker that walks the
// route. Coordinates are metres: x = floor-plan x, z = floor-plan y, y up.
// Drag to orbit, pinch to zoom.
struct Plan3DView: View {
    let indoor: Indoor

    var body: some View {
        SceneView(scene: PlanScene.make(indoor),
                  pointOfView: PlanScene.camera(indoor),
                  options: [.allowsCameraControl, .autoenablesDefaultLighting])
            .background(Color.midnight)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .id(sceneKey)                 // rebuild when the plan changes (elevator toggle)
    }

    private var sceneKey: String {
        "\(indoor.mode)-\(indoor.elevatorOk)-\(indoor.path.count)-\(indoor.rooms.count)"
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

        for room in indoor.rooms where room.polygon.count >= 3 {
            root.addChildNode(floor(room))
            let pts = room.polygon + [room.polygon[0]]
            for (a, b) in zip(pts, pts.dropFirst()) {
                root.addChildNode(wall(a, b, height: wallH))
            }
            root.addChildNode(label(room.name, at: centroid(room.polygon), height: 0.3))
        }

        for door in indoor.doors {
            let marker = SCNNode(geometry: SCNBox(width: 0.25, height: 0.06, length: 0.25, chamferRadius: 0.03))
            marker.geometry?.firstMaterial?.diffuse.contents = door.passable ? UIColor.systemGreen : UIColor.systemRed
            marker.geometry?.firstMaterial?.emission.contents = door.passable ? UIColor.systemGreen : UIColor.systemRed
            marker.position = SCNVector3(Float(door.at.x), 0.05, Float(door.at.y))
            root.addChildNode(marker)
        }

        let pts = (indoor.path3d?.map { SCNVector3(Float($0.x), 0.12, Float($0.z)) })
            ?? indoor.path.map { SCNVector3(Float($0.x), 0.12, Float($0.y)) }
        if pts.count >= 2 {
            for (a, b) in zip(pts, pts.dropFirst()) { root.addChildNode(tube(a, b)) }
            root.addChildNode(sphere(at: pts.first!, color: .systemGreen, radius: 0.18))
            root.addChildNode(sphere(at: pts.last!, color: .systemRed, radius: 0.24))
            root.addChildNode(walker(along: pts))
        }

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .ambient
        light.light?.intensity = 600
        root.addChildNode(light)
        return scene
    }

    static func camera(_ indoor: Indoor) -> SCNNode {
        let node = SCNNode()
        node.camera = SCNCamera()
        node.camera?.zFar = 500
        let cx = Float(indoor.widthM / 2), cz = Float(indoor.heightM / 2)
        let span = Float(max(indoor.widthM, indoor.heightM))
        node.position = SCNVector3(cx, span * 1.05, cz + span * 0.85)
        node.look(at: SCNVector3(cx, 0, cz))
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

    private static func tube(_ a: SCNVector3, _ b: SCNVector3) -> SCNNode {
        let dx = b.x - a.x, dz = b.z - a.z
        let length = (dx * dx + dz * dz).squareRoot()
        let cylinder = SCNCylinder(radius: 0.07, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = pathColor
        cylinder.firstMaterial?.emission.contents = pathColor
        let child = SCNNode(geometry: cylinder)
        child.eulerAngles.z = .pi / 2         // cylinder axis Y -> X
        let parent = SCNNode()
        parent.position = SCNVector3((a.x + b.x) / 2, a.y, (a.z + b.z) / 2)
        parent.eulerAngles.y = atan2(-dz, dx)
        parent.addChildNode(child)
        return parent
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
            let d = Double(((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot())
            actions.append(.move(to: b, duration: max(0.15, d / 1.2)))
        }
        actions.append(.wait(duration: 0.6))
        actions.append(.move(to: pts[0], duration: 0))
        node.runAction(.repeatForever(.sequence(actions)))
        return node
    }

    private static func label(_ text: String, at p: PlanPoint, height: Float) -> SCNNode {
        let t = SCNText(string: text, extrusionDepth: 0)
        t.font = .systemFont(ofSize: 0.35, weight: .medium)
        t.flatness = 0.05
        t.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.85)
        let node = SCNNode(geometry: t)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
        node.position = SCNVector3(Float(p.x), height, Float(p.y))
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    private static func centroid(_ pts: [PlanPoint]) -> PlanPoint {
        PlanPoint(x: pts.map(\.x).reduce(0, +) / Double(pts.count),
                  y: pts.map(\.y).reduce(0, +) / Double(pts.count))
    }
}
