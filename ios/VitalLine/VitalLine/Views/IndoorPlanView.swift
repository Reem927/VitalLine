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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View", selection: $showFloorPlan) {
                    Text("Recommended Plan").tag(false)
                    Text("Floor Plan").tag(true)
                }
                .pickerStyle(.segmented)

                if store.isPlanning {
                    Label("Agents re-planning…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.caution)
                }

                if let plan = store.plan {
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
        if !preview { ElevatorToggle() }

        Plan3DView(indoor: plan.indoor)
            .id(Plan3DView.key(plan.indoor))
            .frame(height: 340)
        Text("Drag to rotate, pinch to zoom. Green door fits the \(equipmentName(plan)); red does not.")
            .font(.caption).foregroundStyle(.textSecondary)

        HeaderCard(plan: plan)

        if let legs = plan.indoor.legs, !legs.isEmpty {
            LegsView(legs: legs).card()
        } else {
            StepsView(steps: plan.steps).card()
        }

        if !preview {
            Button {
                router.push(.arNavigation)
            } label: {
                Label("AR Navigation", systemImage: "arkit").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled((plan.indoor.arRoute ?? []).count < 2)

            Button("Arrived at Patient") {
                store.markAtPatient()
                router.push(.completed)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Floor plan (2D)

    @ViewBuilder
    private func floorPlan(_ plan: Plan) -> some View {
        FloorPlanCanvas(indoor: plan.indoor, showsPath: false)
            .frame(height: 420)
            .card()
        VStack(alignment: .leading, spacing: 8) {
            Text("Floor \(plan.indoor.floor) · \(plan.indoor.doors.count) doors")
                .font(.headline).foregroundStyle(.textPrimary)
            Text("Green fits the \(equipmentName(plan)), red does not. Widths are from the scan; "
                 + "the crew decides the route.")
                .font(.caption).foregroundStyle(.textSecondary)
            ForEach(plan.indoor.doors.sorted { $0.widthIn < $1.widthIn }.prefix(6)) { door in
                HStack {
                    Image(systemName: door.passable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(door.passable ? .success : .critical)
                    Text(String(format: "%.0f in door", door.widthIn)).foregroundStyle(.textPrimary)
                    Spacer()
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func equipmentName(_ plan: Plan) -> String {
        plan.indoor.mode == "stair_chair" ? "stair chair" : "stretcher"
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
