import SwiftUI
import MapKit

// Screen 3: Live Navigation. A simulated drive along the backend's Valhalla route:
// the camera follows the rig with the route ahead, a banner shows the next turn, and the
// six agents tick off live underneath as each one actually finishes. The crew can preview
// the plan before arrival. On arrival the app moves to the indoor plan.
struct LiveNavigationView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router

    // Demo drives are compressed to this many seconds; the real ETA is still shown.
    private let demoDriveSeconds: Double = 90

    @State private var progress: Double = 0          // 0...1 along the route distance
    @State private var camera: MapCameraPosition = .automatic
    @State private var paused = false
    @State private var showPreview = false
    @State private var arrived = false

    var body: some View {
        Group {
            if let outdoor = store.outdoor, outdoor.route.count >= 2 {
                drive(outdoor, RouteGeometry(outdoor.route))
            } else {
                ProgressView("Waiting for the route…").tint(.brandPrimary).padding()
            }
        }
        .navigationTitle("Live Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .vitalScreen()
        .sheet(isPresented: $showPreview) {
            PlanPreviewSheet().presentationDetents([.large])
        }
    }

    // MARK: - Drive

    private func drive(_ outdoor: Outdoor, _ geo: RouteGeometry) -> some View {
        let here = geo.point(at: progress)
        let heading = geo.heading(at: progress)
        let next = nextManeuver(outdoor, geo: geo)

        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Map(position: $camera) {
                    MapPolyline(coordinates: outdoor.route.map(\.coordinate))
                        .stroke(.brandPrimary.opacity(0.35), lineWidth: 8)
                    MapPolyline(coordinates: geo.remaining(from: progress))
                        .stroke(.brandPrimary, lineWidth: 8)
                    Annotation("", coordinate: here) {
                        Image(systemName: "location.north.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.brandPrimary, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    Marker("Entrance", systemImage: "door.left.hand.open",
                           coordinate: outdoor.entrance.coordinate)
                        .tint(.success)
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .onAppear { follow(here, heading) }
                .onChange(of: progress) { follow(geo.point(at: progress), geo.heading(at: progress)) }

                banner(next, arrivedText: arrived ? "Arrived at \(store.dispatch?.address ?? "destination")" : nil)
                    .padding()
            }

            panel(outdoor)
        }
        .task(id: paused) { await run(geo) }
    }

    private func follow(_ c: CLLocationCoordinate2D, _ heading: Double) {
        withAnimation(.linear(duration: 0.5)) {
            camera = .camera(MapCamera(centerCoordinate: c, distance: 650, heading: heading, pitch: 55))
        }
    }

    // Advance the rig along the route; stops at the end.
    private func run(_ geo: RouteGeometry) async {
        guard !paused, !arrived else { return }
        let tick = 0.5
        while !Task.isCancelled, progress < 1, !paused {
            try? await Task.sleep(for: .milliseconds(Int(tick * 1000)))
            progress = min(1, progress + tick / demoDriveSeconds)
        }
        if progress >= 1 { arrive() }
    }

    private func arrive() {
        guard !arrived else { return }
        arrived = true
        store.markArrivedAtBuilding()
    }

    // MARK: - Banner and panel

    private func nextManeuver(_ outdoor: Outdoor, geo: RouteGeometry) -> (text: String, meters: Double, type: Int?)? {
        guard let maneuvers = outdoor.maneuvers, !maneuvers.isEmpty else { return nil }
        let travelled = progress * geo.totalMeters
        let upcoming = maneuvers.first { geo.meters(atIndex: $0.shapeIndex) > travelled + 1 } ?? maneuvers.last!
        return (upcoming.text, max(0, geo.meters(atIndex: upcoming.shapeIndex) - travelled), upcoming.type)
    }

    private func banner(_ next: (text: String, meters: Double, type: Int?)?, arrivedText: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: arrivedText != nil ? "flag.checkered" : turnIcon(next?.type))
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                if let arrivedText {
                    Text(arrivedText).font(.headline)
                } else if let next {
                    Text(distanceText(next.meters)).font(.title3.bold())
                    Text(next.text).font(.subheadline).lineLimit(2)
                } else {
                    Text("Follow the route").font(.headline)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding()
        .background(Color.success.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
    }

    private func panel(_ outdoor: Outdoor) -> some View {
        let etaMin = Double(outdoor.etaMinutes ?? 0) * (1 - progress)
        let km = (outdoor.distanceKm ?? 0) * (1 - progress)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(arrived ? "Arrived" : "\(Int(etaMin.rounded(.up))) min")
                        .font(.title2.bold()).foregroundStyle(.success)
                    Text(arrived ? "Building entrance" :
                            "\(String(format: "%.1f", km)) km · arrive \(arrivalTime(etaMin))")
                        .font(.caption).foregroundStyle(.textSecondary)
                }
                Spacer()
                if !arrived {
                    Button(paused ? "Resume" : "Pause") { paused.toggle() }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(width: 110)
                }
            }
            Text("Simulated drive · \(speedText(outdoor))")
                .font(.caption2).foregroundStyle(.textSecondary)

            AgentTicksView(tasks: store.tasks, done: store.agentsDone)

            if let message = store.errorMessage, !store.isPlanning {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.critical)
            }

            HStack(spacing: 12) {
                Button("Preview Plan") { showPreview = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.plan == nil)
                    .opacity(store.plan == nil ? 0.4 : 1)
                Button(arrived ? "Indoor Plan" : "Skip to Arrival") {
                    if arrived { router.push(.indoorPlan) } else { progress = 1; arrive() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(arrived && store.plan == nil)
            }
        }
        .padding()
        .background(Color.surface)
        .onChange(of: arrived) { goIndoorWhenReady() }
        .onChange(of: store.agentsDone) { goIndoorWhenReady() }
    }

    // On arrival, open the indoor plan as soon as every agent has finished.
    private func goIndoorWhenReady() {
        if arrived, store.agentsDone, router.path.last == .liveNavigation {
            router.push(.indoorPlan)
        }
    }

    // Valhalla maneuver types: 9-11 right, 14-16 left, 4-6 destination, others straight.
    private func turnIcon(_ type: Int?) -> String {
        switch type ?? 0 {
        case 9, 10, 11: return "arrow.turn.up.right"
        case 14, 15, 16: return "arrow.turn.up.left"
        case 12, 13: return "arrow.uturn.down"
        case 4, 5, 6: return "mappin.circle.fill"
        default: return "arrow.up"
        }
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int((meters / 10).rounded()) * 10) m"
    }

    private func arrivalTime(_ minutes: Double) -> String {
        Date.now.addingTimeInterval(minutes * 60).formatted(date: .omitted, time: .shortened)
    }

    private func speedText(_ outdoor: Outdoor) -> String {
        guard let eta = outdoor.etaMinutes, eta > 0 else { return "demo speed" }
        return String(format: "%.0fx speed", Double(eta) * 60 / demoDriveSeconds)
    }
}

// Read-only plan preview shown during the drive. Dismisses itself.
struct PlanPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            IndoorPlanView(preview: true)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// The six agents, each pending, then a spinner while it runs, then a tick when done.
struct AgentTicksView: View {
    let tasks: [AgentTask]
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(done ? "Plan Ready" : "Agents planning…")
                .font(.headline).foregroundStyle(.textPrimary)
            ForEach(tasks) { task in
                HStack(spacing: 10) {
                    Group {
                        if task.isDone {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.success)
                        } else if task.isFailed {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.critical)
                        } else if task.isRunning {
                            ProgressView().tint(.brandPrimary)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.textSecondary)
                        }
                    }
                    .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title).font(.subheadline).foregroundStyle(.textPrimary)
                        if let detail = task.detail {
                            Text(detail).font(.caption2).foregroundStyle(.textSecondary).lineLimit(1)
                        }
                    }
                }
                .animation(.default, value: task.status)
            }
        }
    }
}

// Distances along the route polyline, to place the rig and find the next turn.
struct RouteGeometry {
    let coords: [CLLocationCoordinate2D]
    let cumulative: [Double]           // metres from the start to each point
    var totalMeters: Double { cumulative.last ?? 0 }

    init(_ route: [LatLon]) {
        coords = route.map(\.coordinate)
        var acc: [Double] = [0]
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            acc.append(acc[i - 1] + a.distance(from: b))
        }
        cumulative = acc
    }

    func meters(atIndex i: Int) -> Double { cumulative[min(max(i, 0), cumulative.count - 1)] }

    private func segment(at progress: Double) -> (i: Int, t: Double) {
        let d = progress * totalMeters
        guard let j = cumulative.firstIndex(where: { $0 >= d }), j > 0 else { return (0, 0) }
        let span = cumulative[j] - cumulative[j - 1]
        return (j - 1, span > 0 ? (d - cumulative[j - 1]) / span : 0)
    }

    func point(at progress: Double) -> CLLocationCoordinate2D {
        let (i, t) = segment(at: progress)
        let a = coords[i], b = coords[min(i + 1, coords.count - 1)]
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    func heading(at progress: Double) -> Double {
        let (i, _) = segment(at: progress)
        let a = coords[i], b = coords[min(i + 1, coords.count - 1)]
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la = a.latitude * .pi / 180, lb = b.latitude * .pi / 180
        let y = sin(dLon) * cos(lb)
        let x = cos(la) * sin(lb) - sin(la) * cos(lb) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    func remaining(from progress: Double) -> [CLLocationCoordinate2D] {
        let (i, _) = segment(at: progress)
        return [point(at: progress)] + coords[(i + 1)...]
    }
}
