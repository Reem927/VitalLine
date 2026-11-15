import SwiftUI

// TEMPORARY stand-ins for Person B's screens, so the full flow runs today.
// When Person B adds the real file (e.g. LiveNavigationView.swift),
// delete the matching struct from this file. When all are replaced,
// delete this file.

// LiveNavigationView and IndoorPlanView now live in their own files.

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
