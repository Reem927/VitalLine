import SwiftUI

// TEMPORARY stand-ins for Person B's screens, so the full flow runs today.
// When Person B adds the real file (e.g. LiveNavigationView.swift),
// delete the matching struct from this file. When all are replaced,
// delete this file.

// LiveNavigationView and IndoorPlanView now live in their own files.

struct SettingsView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage("scenarioId") private var scenarioId = "houston-cardiac-14"

    var body: some View {
        List {
            LabeledContent("Data", value: API.useMock ? "Mock (synthetic)" : "Live backend")
                .listRowBackground(Color.surface)
            Section {
                Picker("Scenario", selection: $scenarioId) {
                    Text("Houston demo building").tag("houston-cardiac-14")
                    Text("Princeton on-site AR test").tag("princeton-live")
                }
                .listRowBackground(Color.surface)
            } footer: {
                Text("Changing the scenario loads a new synthetic call on the Dispatch tab.")
            }
        }
        .onChange(of: scenarioId) {
            router.popToRoot()
            Task { await store.load() }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .vitalScreen()
    }
}
