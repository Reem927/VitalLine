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
    @State private var confirmLogOut = false
    @State private var showNoAccount = false

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
            Section {
                LabeledContent("Crew unit", value: Crew.unit)
                    .listRowBackground(Color.surface)
                Button("Log Out", role: .destructive) { confirmLogOut = true }
                    .listRowBackground(Color.surface)
            } header: {
                Text("Account")
            }
        }
        .confirmationDialog("Log out of VitalLine?", isPresented: $confirmLogOut, titleVisibility: .visible) {
            // Sign-in is not connected yet: this is where the auth sign-out call goes.
            Button("Log Out", role: .destructive) { showNoAccount = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Sign-in is not set up yet", isPresented: $showNoAccount) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Accounts will be connected later. Nothing was changed.")
        }
        .onChange(of: scenarioId) {
            router.popToRoot()
            Task { await store.load() }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .vitalScreen()
    }
}
