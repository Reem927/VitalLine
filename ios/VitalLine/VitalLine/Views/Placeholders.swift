import SwiftUI

// TEMPORARY stand-ins for Person B's screens, so the full flow runs today.
// When Person B adds the real file (e.g. LiveNavigationView.swift),
// delete the matching struct from this file. When all are replaced,
// delete this file.

struct LiveNavigationView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let outdoor = store.outdoor {
                    RouteMapView(outdoor: outdoor)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Agent progress (Person B: AgentProgressView replaces this block)
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.agentsDone ? "Plan Ready" : "Creating Plan…")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                    ForEach(store.tasks) { task in
                        HStack(spacing: 10) {
                            if task.isDone {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.success)
                            } else if task.isFailed {
                                Image(systemName: "xmark.octagon.fill").foregroundStyle(.critical)
                            } else if task.isRunning {
                                ProgressView().tint(.brandPrimary)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.textSecondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).foregroundStyle(.textPrimary)
                                if let detail = task.detail {
                                    Text(detail).font(.caption).foregroundStyle(.textSecondary)
                                }
                            }
                        }
                        .animation(.default, value: task.status)
                    }
                    if let message = store.errorMessage, !store.isPlanning {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.critical)
                        Button("Retry") { Task { await store.replan() } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .card()

                Button("View Indoor Plan") {
                    store.markArrivedAtBuilding()
                    router.push(.indoorPlan)
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!store.agentsDone)
                    .opacity(store.agentsDone ? 1 : 0.4)
            }
            .padding()
        }
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

                if store.isPlanning {
                    Label("Agents re-planning…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.caution)
                }

                if let plan = store.plan {
                    if showFloorPlan {
                        FloorPlanCanvas(indoor: plan.indoor, showsPath: false)
                            .frame(height: 360)
                            .card()
                    } else {
                        FloorPlanCanvas(indoor: plan.indoor)
                            .frame(height: 260)
                            .card()
                        HeaderCard(plan: plan)
                        StepsView(steps: plan.steps).card()
                    }
                }

                Button("Arrived at Patient") {
                    store.markAtPatient()
                    router.push(.completed)
                }
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
