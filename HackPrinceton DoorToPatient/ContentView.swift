import SwiftUI

struct ContentView: View {
    @State private var store = PlanStore()

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.plan {
                    PlanView(plan: plan, store: store)
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
            .navigationTitle("Door-to-Patient")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await store.load() }
    }
}

#Preview {
    ContentView()
}
