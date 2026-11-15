import SwiftUI

// Screen 4: Indoor Plan.
//   Recommended Plan: the route in 3D, each leg marked real (scan) or modeled, the steps,
//                     and AR navigation along the same route.
//   Floor Plan:       the 2D plan of the floor with every door and its width, so the crew
//                     can make their own choice. No forced path, no AR.
// `preview` is the read-only version shown from Live Navigation before arrival.
struct IndoorPlanView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router
    var preview = false
    @State private var showFloorPlan = false
    @State private var page = 0            // 0 = outside (aerial), 1 = inside (scan)
    @State private var showWalkthrough = false
    @State private var fitFor = "stretcher"   // equipment checked on the Floor Plan page

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View", selection: $showFloorPlan) {
                    Text("Recommended Plan").tag(false)
                    Text("Floor Plan").tag(true)
                }
                .pickerStyle(.segmented)

                if let plan = store.shownPlan {
                    if showFloorPlan { floorPlan(plan) } else { recommended(plan) }
                } else {
                    ProgressView("Plan still building…").tint(.brandPrimary)
                }
            }
            .padding()
        }
        .navigationTitle(preview ? "Plan Preview" : "Indoor Plan")
        .navigationBarTitleDisplayMode(.inline)
        .vitalScreen()
    }

    // MARK: - Recommended (3D)

    @ViewBuilder
    private func recommended(_ plan: Plan) -> some View {
        if !preview, plan.indoor.elevatorOutVariant != nil { ElevatorToggle() }

        if let aerial = plan.outdoor.aerial {
            // Slide between the outside view (where to stop) and the inside view (the route).
            Picker("View", selection: $page) {
                Text("1 · Outside").tag(0)
                Text("2 · Inside").tag(1)
            }
            .pickerStyle(.segmented)
            TabView(selection: $page) {
                AerialView(aerial: aerial).tag(0)
                Plan3DView(indoor: plan.indoor)
                    .id(Plan3DView.key(plan.indoor))
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)
            .animation(.easeInOut, value: page)
            if page == 0 {
                AerialLegend(aerial: aerial).card()
            } else {
                Text("Drag to rotate, pinch to zoom. Green door fits the \(equipmentName(plan)); red does not.")
                    .font(.caption).foregroundStyle(.textSecondary)
            }
        } else {
            Plan3DView(indoor: plan.indoor)
                .id(Plan3DView.key(plan.indoor))
                .frame(height: 340)
            Text("Drag to rotate, pinch to zoom. Green door fits the \(equipmentName(plan)); red does not.")
                .font(.caption).foregroundStyle(.textSecondary)
        }

        HeaderCard(plan: plan)

        if let legs = plan.indoor.legs, !legs.isEmpty {
            LegsView(legs: legs).card()
        } else {
            StepsView(steps: plan.steps).card()
        }

        if !preview {
            // Live AR needs the crew inside the scanned building, which only the on-site
            // scenario has. Elsewhere the same route plays as a walkthrough of the real scans.
            if plan.indoor.nav != nil {
                Button {
                    router.push(.arNavigation)
                } label: {
                    Label("AR Navigation", systemImage: "arkit").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    showWalkthrough = true
                } label: {
                    Label("Route Walkthrough", systemImage: "figure.walk").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .fullScreenCover(isPresented: $showWalkthrough) {
                    WalkthroughScreen(indoor: plan.indoor)
                }
            }

            Button("Arrived at Patient") {
                store.markAtPatient()
                router.push(.completed)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Floor plan (2D)

    // Doors recoloured for the equipment picked on this page.
    private func doors(_ plan: Plan) -> [Door] {
        plan.indoor.doors.map { door in
            var d = door
            if let fit = door.fits?[fitFor] { d.passable = fit == "pass" }
            return d
        }
    }

    @ViewBuilder
    private func floorPlan(_ plan: Plan) -> some View {
        let checked = doors(plan)
        let fitting = checked.filter(\.passable).count
        let name = fitFor == "stair_chair" ? "stair chair" : "stretcher"

        Picker("Check fit for", selection: $fitFor) {
            Text("Stretcher").tag("stretcher")
            Text("Stair chair").tag("stair_chair")
        }
        .pickerStyle(.segmented)

        FloorPlanCanvas(indoor: { var i = plan.indoor; i.doors = checked; return i }(),
                        showsPath: false, showsDoors: true)
            .frame(height: 380)
            .card()

        VStack(alignment: .leading, spacing: 6) {
            Text("\(fitting) of \(checked.count) doors fit the \(name)")
                .font(.headline).foregroundStyle(.textPrimary)
            Text("Checked for door width and the turn into the next room. Numbers on the plan are door widths in inches. The crew decides the route.")
                .font(.caption).foregroundStyle(.textSecondary)
        }
        .card()

        VStack(alignment: .leading, spacing: 10) {
            Text("Doors on floor \(plan.indoor.floor)").font(.headline).foregroundStyle(.textPrimary)
            ForEach(checked.sorted { ($0.passable ? 1 : 0, $0.widthIn) < ($1.passable ? 1 : 0, $1.widthIn) }) { door in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: door.passable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(door.passable ? .success : .critical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(door.between ?? "Door").font(.subheadline).foregroundStyle(.textPrimary)
                        Text(detail(door))
                            .font(.caption).foregroundStyle(.textSecondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f in", door.widthIn))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.textPrimary)
                }
            }
        }
        .card()

        let unknowns = (plan.indoor.legs ?? []).filter { !$0.real }
        if !unknowns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Not in the scan data", systemImage: "questionmark.circle")
                    .font(.headline).foregroundStyle(.caution)
                ForEach(unknowns) { leg in
                    Text(leg.text).font(.footnote).foregroundStyle(.textPrimary)
                }
            }
            .card()
        }
    }

    private func detail(_ door: Door) -> String {
        var parts: [String] = []
        if let why = door.blockedBy?[fitFor], !door.passable { parts.append(why) }
        if let measured = door.measured { parts.append(measured ? "measured in the scan" : "default size, not measured") }
        if let kind = door.opening, kind != "doorway" { parts.append("open passage") }
        return parts.isEmpty ? "width from the scan" : parts.joined(separator: " · ")
    }

    private func equipmentName(_ plan: Plan) -> String {
        plan.indoor.mode == "stair_chair" ? "stair chair" : "stretcher"
    }
}

// Full-screen simulated walkthrough: the camera follows the route through the real scans,
// entrance first, then the unit. No phone camera is used.
struct WalkthroughScreen: View {
    let indoor: Indoor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.midnight.ignoresSafeArea()
            Plan3DView(indoor: indoor, autoWalk: true)
                .padding(.top, 56)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Color.surface, in: Circle())
                        .foregroundStyle(.textPrimary)
                }
                Spacer()
                Text("Simulated walkthrough · real scans, not live camera")
                    .font(.caption).foregroundStyle(.textSecondary)
            }
            .padding(.horizontal).padding(.top, 8)
        }
        .preferredColorScheme(.dark)
    }
}

// Route legs, each badged as scan data or modeled/estimated.
struct LegsView: View {
    let legs: [Leg]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(legs) { leg in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(leg.kind))
                        .foregroundStyle(.brandPrimary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(leg.text).foregroundStyle(.textPrimary).font(.subheadline)
                        Text(leg.real ? "SCAN DATA" : "MODELED")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((leg.real ? Color.success : Color.caution).opacity(0.18), in: Capsule())
                            .foregroundStyle(leg.real ? .success : .caution)
                    }
                }
            }
        }
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "elevator": return "arrow.up.arrow.down.square"
        case "stairs": return "figure.stairs"
        default: return "figure.walk"
        }
    }
}
