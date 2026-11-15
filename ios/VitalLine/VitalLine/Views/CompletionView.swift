import SwiftUI

// Screen 8: Response Completed. Yes saves to History, No returns to Dispatch.
struct CompletionView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(HistoryStore.self) private var history
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 110, weight: .light))
                .foregroundStyle(.brandPrimary)
                .symbolEffect(.bounce, value: appeared)

            Text("Completed!")
                .font(.largeTitle.bold())
                .foregroundStyle(.textPrimary)

            Text("Save to History?")
                .font(.title3)
                .foregroundStyle(.textSecondary)

            Spacer()

            Button("Yes") {
                if let plan = store.plan { history.save(plan, events: store.events) }
                store.complete(save: true)
                router.popToRoot()
                router.selectedTab = .history
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("No") {
                store.complete(save: false)
                router.popToRoot()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(24)
        .navigationBarBackButtonHidden(true)
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear { appeared = true }
        .vitalScreen()
    }
}
