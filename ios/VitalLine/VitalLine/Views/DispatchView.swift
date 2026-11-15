import SwiftUI

// Screen 1: Dispatch (Home). Shows the current call and a Start Response button.
struct DispatchView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VitalLineHeader()

                Text("Incoming Dispatch")
                    .font(.title2.bold())
                    .foregroundStyle(.textPrimary)

                if let dispatch = store.dispatch {
                    DispatchCard(dispatch: dispatch)

                    Button("Start Response") {
                        Task { await store.startResponse() }   // all six agents start now
                        router.push(.routePreview)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
                } else if let message = store.errorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Couldn't load dispatch", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(.caution)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.textSecondary)
                        Button("Try again") { Task { await store.load() } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .card()
                } else {
                    ProgressView("Waiting for dispatch…")
                        .tint(.brandPrimary)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .refreshable { await store.load() }
        .toolbar(.hidden, for: .navigationBar)
        .vitalScreen()
    }
}
