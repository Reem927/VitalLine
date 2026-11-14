import SwiftUI

// TEMPORARY stand-ins for Person B's screens, so the full flow runs today.
// When Person B adds the real file (e.g. LiveNavigationView.swift),
// delete the matching struct from this file. When all are replaced,
// delete this file.

struct LiveNavigationView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            if let plan = store.plan {
                RouteMapView(outdoor: plan.outdoor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text("Placeholder: live navigation + agent progress")
                .font(.footnote)
                .foregroundStyle(.textSecondary)
            Button("View Indoor Plan") { router.push(.indoorPlan) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .navigationTitle("Live Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .vitalScreen()
    }
}

struct IndoorPlanView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showFloorPlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View", selection: $showFloorPlan) {
                    Text("Recommended Plan").tag(false)
                    Text("Floor Plan").tag(true)
                }
                .pickerStyle(.segmented)

                ElevatorToggle()

                if let plan = store.plan {
                    if showFloorPlan {
                        FloorPlanCanvas(indoor: plan.indoor)
                            .frame(height: 320)
                            .card()
                    } else {
                        HeaderCard(plan: plan)
                        StepsView(steps: plan.steps).card()
                    }
                }

                Button("Arrived at Patient") { router.push(.completed) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding()
        }
        .navigationTitle("Indoor Plan")
        .navigationBarTitleDisplayMode(.inline)
        .vitalScreen()
    }
}

struct ARNavigationView: View {
    var body: some View {
        Text("AR navigation (optional idea)")
            .foregroundStyle(.textSecondary)
            .vitalScreen()
    }
}

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history

    var body: some View {
        List {
            if history.entries.isEmpty {
                Text("No saved responses yet")
                    .foregroundStyle(.textSecondary)
            }
            ForEach(history.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.plan.dispatch.complaint).foregroundStyle(.textPrimary)
                    Text(entry.plan.dispatch.address)
                        .font(.caption).foregroundStyle(.textSecondary)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.textSecondary)
                }
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("History")
        .vitalScreen()
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            LabeledContent("Data", value: API.useMock ? "Mock (synthetic)" : "Live backend")
                .listRowBackground(Color.surface)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .vitalScreen()
    }
}
