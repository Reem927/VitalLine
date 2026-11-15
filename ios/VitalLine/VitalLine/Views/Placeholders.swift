import SwiftUI

// TEMPORARY stand-ins for Person B's screens, so the full flow runs today.
// When Person B adds the real file (e.g. LiveNavigationView.swift),
// delete the matching struct from this file. When all are replaced,
// delete this file.

// LiveNavigationView and IndoorPlanView now live in their own files.

struct SettingsView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AuthStore.self) private var auth
    @Environment(HistoryStore.self) private var history
    @AppStorage("scenarioId") private var scenarioId = "houston-cardiac-14"
    @AppStorage("backendURL") private var backendURL = ""
    @AppStorage("demoToken") private var demoToken = ""
    @State private var connection: String?
    @State private var testing = false
    @State private var confirmLogOut = false

    var body: some View {
        List {
            LabeledContent("Data", value: API.useMock ? "Mock (synthetic)" : "Live backend")
                .listRowBackground(Color.surface)
            Section {
                TextField(API.defaultBaseURL.isEmpty ? "Tunnel address (https://...)" : API.defaultBaseURL,
                          text: $backendURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .listRowBackground(Color.surface)
                SecureField("Demo token", text: $demoToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .listRowBackground(Color.surface)
                Button(testing ? "Testing…" : "Test Connection") {
                    testing = true
                    Task {
                        connection = await API.testConnection()
                        testing = false
                        if connection == "Connected." { await store.load() }
                    }
                }
                .disabled(testing)
                .listRowBackground(Color.surface)
                if let connection {
                    Text(connection).font(.footnote)
                        .foregroundStyle(connection == "Connected." ? .success : .caution)
                        .listRowBackground(Color.surface)
                }
            } header: {
                Text("Backend")
            } footer: {
                Text("On a phone, paste the address and token that scripts/run_tunnel.sh prints on the Mac.")
            }
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
                LabeledContent("Signed in as", value: auth.email ?? "Guest (sign-in is off)")
                    .listRowBackground(Color.surface)
                LabeledContent("Crew unit", value: Crew.unit)
                    .listRowBackground(Color.surface)
                Button("Log Out", role: .destructive) { confirmLogOut = true }
                    .listRowBackground(Color.surface)
            } header: {
                Text("Account")
            }
        }
        .confirmationDialog("Log out of VitalLine?", isPresented: $confirmLogOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task {
                    await API.signOut()          // ends the session on the backend
                    history.entries = []
                    router.popToRoot()
                    router.selectedTab = .dispatch
                    auth.signOut()               // back to the sign-in screen
                }
            }
            Button("Cancel", role: .cancel) {}
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
