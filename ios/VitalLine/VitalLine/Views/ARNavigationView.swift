import SwiftUI
import ARKit
import RealityKit
import UIKit
import simd

// MARK: - Backend contract
// indoor.ar_route: metres, origin at the route's first point, Y up, first leg along -Z.
// The crew stands at the first point (the start of the recommended route) and faces the
// first leg, then starts AR. The sample route is used only when the plan has no AR route.
private struct VLWaypoint {
    let x: Float
    let y: Float
    let z: Float

    var position: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

private struct VLRoute {
    let waypoints: [VLWaypoint]
    // Optional USDZ resource in the app bundle, without the .usdz extension.
    let modelResourceName: String?
}

private enum VLDemoRoute {
    static let sample = VLRoute(
        waypoints: [
            VLWaypoint(x: 0, y: 0, z: 0),
            VLWaypoint(x: 0, y: 0, z: -2),
            VLWaypoint(x: 0, y: 0, z: -4),
            VLWaypoint(x: 2, y: 0, z: -4),
            VLWaypoint(x: 4, y: 0, z: -4)
        ],
        modelResourceName: nil
    )
}

// MARK: - User interface
struct ARNavigationView: View {
    @Environment(PlanStore.self) private var store
    @State private var alignmentVersion = 0
    @State private var clearVersion = 0
    @State private var isAligned = false

    private var planRoute: VLRoute? {
        guard let pts = store.plan?.indoor.arRoute, pts.count >= 2 else { return nil }
        return VLRoute(waypoints: pts.map { VLWaypoint(x: Float($0.x), y: Float($0.y), z: Float($0.z)) },
                       modelResourceName: nil)
    }

    private var startPlace: String {
        store.plan?.indoor.legs?.last.map { _ in "the unit door" } ?? "the route start"
    }

    var body: some View {
        ZStack {
            VLRouteCamera(
                route: planRoute ?? VLDemoRoute.sample,
                alignmentVersion: alignmentVersion,
                clearVersion: clearVersion
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "location.north.line.fill")
                        .foregroundStyle(.cyan)
                    Text("VITALLINE AR")
                        .font(.headline)
                    Spacer()
                    Text(planRoute == nil ? "SAMPLE" : "PLAN ROUTE")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }
                .padding()
                .background(.black.opacity(0.78))

                Spacer()

                VStack(spacing: 12) {
                    Text(isAligned ? (planRoute == nil ? "Sample route displayed" : "Follow the chevrons")
                                   : "Align at \(startPlace)")
                        .font(.headline)
                    Text(isAligned
                         ? "Chevrons follow the recommended route. Tracking can drift; realign if needed."
                         : "Stand at \(startPlace), face into the unit along the first leg, then start.")
                        .font(.caption)
                        .multilineTextAlignment(.center)

                    Button {
                        alignmentVersion += 1
                        isAligned = true
                    } label: {
                        Label(isAligned ? "Realign Route" : "Start AR Route", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    Button("Clear Route") {
                        clearVersion += 1
                        isAligned = false
                    }
                    .foregroundStyle(.white)

                    Text("Prototype only — not for real emergency navigation.")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                .padding()
            }
        }
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
    }
}
// MARK: - Camera and route renderer
private struct VLRouteCamera: UIViewRepresentable {
    let route: VLRoute
    let alignmentVersion: Int
    let clearVersion: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        view.session.run(configuration)
        context.coordinator.arView = view
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let coordinator = context.coordinator
        // Clearing first avoids re-rendering a route that was just cleared.
        if coordinator.lastClearVersion != clearVersion {
            coordinator.lastClearVersion = clearVersion
            coordinator.clear()
        }
        if coordinator.lastAlignmentVersion != alignmentVersion {
            coordinator.lastAlignmentVersion = alignmentVersion
            coordinator.show(route: route)
        }
    }

    final class Coordinator {
        weak var arView: ARView?
        var lastAlignmentVersion = 0
        var lastClearVersion = 0
        private var routeAnchor: AnchorEntity?

        func clear() {
            if let routeAnchor, let arView {
                arView.scene.removeAnchor(routeAnchor)
            }
            routeAnchor = nil
        }

        func show(route: VLRoute) {
            guard let arView, route.waypoints.count >= 2 else { return }
            clear()

            // PLACEHOLDER ALIGNMENT: assume phone starts at the first waypoint
            // and faces along the model's -Z direction. This is NOT automatic
            // recognition of a building. Replace with a verified model-to-AR
            // transform when a localization system is available.
            let camera = arView.cameraTransform
            let forward = SIMD3<Float>(
                -camera.matrix.columns.2.x,
                0,
                -camera.matrix.columns.2.z
            )
            guard simd_length(forward) > 0.001 else { return }
            let heading = simd_normalize(forward)
            let yaw = atan2(-heading.x, -heading.z)
            let rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let start = route.waypoints[0].position
            // Demo calibration: assume the phone is about 1.25 m above the floor.
            // Replace with a measured entrance/floor pose for real alignment.
            let assumedCameraHeight: Float = 1.25
            let origin = camera.translation - rotation.act(start)
                - SIMD3<Float>(0, assumedCameraHeight, 0)

            let anchor = AnchorEntity(world: origin)
            let content = Entity()
            content.orientation = rotation
            anchor.addChild(content)

            // OPTIONAL BUILDING MODEL: Add a USDZ to the app target and set
            // modelResourceName. Its origin, axes and meter scale MUST match
            // the route's coordinates. This model may obscure camera imagery;
            // use transparent or hidden geometry for a navigation overlay.
            if let name = route.modelResourceName,
               let model = try? Entity.loadModel(named: name) {
                model.isEnabled = false // Enable only for model-alignment debugging.
                content.addChild(model)
            }

            let points = route.waypoints.map(\.position)
            for index in 0..<(points.count - 1) {
                let startPoint = points[index]
                let endPoint = points[index + 1]
                let segment = endPoint - startPoint
                let distance = simd_length(segment)
                if distance < 0.05 { continue }

                let direction = simd_normalize(segment)
                let numberOfArrows = max(1, Int(ceil(distance / 0.9)))
                for step in 0..<numberOfArrows {
                    let t = (Float(step) + 0.5) / Float(numberOfArrows)
                    let arrow = makeArrow()
                    // Route y=0 denotes floor height; arrows float just above it.
                    arrow.position = startPoint + segment * t + SIMD3<Float>(0, 0.025, 0)
                    arrow.orientation = simd_quatf(
                        angle: atan2(-direction.x, -direction.z),
                        axis: SIMD3<Float>(0, 1, 0)
                    )
                    content.addChild(arrow)
                }
            }
            arView.scene.addAnchor(anchor)
                      routeAnchor = anchor
                  }

                  // Two flat cyan bars form a forward-pointing chevron on the floor.
                  // The local forward direction is -Z; route rotation is applied above.
                  private func makeArrow() -> Entity {
                      let arrow = Entity()
                      let material = UnlitMaterial(color: UIColor.cyan)
                      let barLength: Float = 0.48
                      let barWidth: Float = 0.105
                      let barThickness: Float = 0.012

                      let left = ModelEntity(
                          mesh: .generateBox(
                              width: barWidth,
                              height: barThickness,
                              depth: barLength
                          ),
                          materials: [material]
                      )
                      left.position = SIMD3<Float>(-0.16, 0, 0)
                      left.orientation = simd_quatf(
                          angle: -.pi / 4,
                          axis: SIMD3<Float>(0, 1, 0)
                      )
                      arrow.addChild(left)

                      let right = ModelEntity(
                          mesh: .generateBox(
                              width: barWidth,
                              height: barThickness,
                              depth: barLength
                          ),
                          materials: [material]
                      )
                      right.position = SIMD3<Float>(0.16, 0, 0)
                      right.orientation = simd_quatf(
                          angle: .pi / 4,
                          axis: SIMD3<Float>(0, 1, 0)
                      )
                      arrow.addChild(right)
                      return arrow
                  }
              }
          }
#Preview {
    NavigationStack {
        ARNavigationView()
    }
}



