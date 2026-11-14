import SwiftUI

// Shared wrapper for every tab: navigation bar, loading and error states.
// `content` is only shown once a plan has loaded.
struct PlanTab<Content: View>: View {
    let title: String
    let store: PlanStore
    @ViewBuilder let content: (Plan) -> Content

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.plan {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            content(plan)
                        }
                        .padding()
                    }
                    .background(Color.midnight)
                } else if let message = store.errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load plan", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await store.load() } }
                    }
                } else {
                    ProgressView("Planning door-to-patient route…")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if store.isLoading && store.plan != nil {
                    ProgressView("Re-planning…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

// Tab 1: getting from the rig to the door.
struct RouteTab: View {
    let plan: Plan

    var body: some View {
        HeaderCard(plan: plan)

        SectionTitle("Outdoor approach")
        RouteMapView(outdoor: plan.outdoor)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        FlagsList(flags: plan.outdoor.flags)

        SectionTitle("Access")
        AccessNotesView(notes: plan.access)
    }
}

// Tab 2: inside the building. The elevator toggle lives here
// because this is where the demo twist is most visible.
struct FloorTab: View {
    let plan: Plan
    @Bindable var store: PlanStore

    var body: some View {
        HeaderCard(plan: plan)

        Toggle(isOn: $store.elevatorOut) {
            Label("Elevator out of service", systemImage: "arrow.up.arrow.down.square")
        }
        .tint(.critical)
        .card()
        .sensoryFeedback(.impact, trigger: store.elevatorOut)
        .onChange(of: store.elevatorOut) {
            Task { await store.load() }
        }

        SectionTitle("Steps")
        StepsView(steps: plan.steps)
            .card()
        
        SectionTitle("\(plan.building.name)")
        FloorPlanView(indoor: plan.indoor)
            .frame(height: 320)
            .card()

        
    }
}

// Tab 3: the five-line brief and the Wolfram proof.
struct BriefTab: View {
    let plan: Plan

    var body: some View {
        HeaderCard(plan: plan)

        SectionTitle("Crew brief")
        BriefView(lines: plan.brief, verification: plan.verification)
            .card()

        Text("Decision aid only. The crew decides. Demo data is synthetic.")
            .font(.footnote)
            .foregroundStyle(.textSecondary)
    }
}
