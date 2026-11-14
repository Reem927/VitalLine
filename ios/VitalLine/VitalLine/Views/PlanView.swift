import SwiftUI

// The main crew screen: one scrolling column of cards.
struct PlanView: View {
    let plan: Plan
    @Bindable var store: PlanStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderCard(plan: plan)

                Toggle(isOn: $store.elevatorOut) {
                    Label("Elevator out of service", systemImage: "arrow.up.arrow.down.square")
                }
                .tint(.critical)
                .card()
                .sensoryFeedback(.impact, trigger: store.elevatorOut)   // haptic buzz
                .onChange(of: store.elevatorOut) {
                    Task { await store.load() }
                }

                SectionTitle("Outdoor approach")
                RouteMapView(outdoor: plan.outdoor)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                FlagsList(flags: plan.outdoor.flags)

                SectionTitle("Access")
                AccessNotesView(notes: plan.access)

                SectionTitle("Floor \(plan.indoor.floor) · \(plan.building.name)")
                FloorPlanView(indoor: plan.indoor)
                    .frame(height: 300)
                    .card()

                SectionTitle("Steps")
                StepsView(steps: plan.steps)
                    .card()

                SectionTitle("Crew brief")
                BriefView(lines: plan.brief, verification: plan.verification)
                    .card()

                Text("Decision aid only. The crew decides. Demo data is synthetic.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
            }
            .padding()
        }
        .overlay {
            if store.isLoading {
                ProgressView("Re-planning…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.title3.bold()).padding(.top, 8)
    }
}

extension View {
    // Reusable card look: padding + rounded translucent background.
    func card() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

func minutesText(_ seconds: Int) -> String {
    String(format: "%.1f", Double(seconds) / 60.0)
}

#Preview {
    let store = PlanStore()
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let plan = try! decoder.decode(Plan.self, from: Data(MockData.stretcherJSON.utf8))
    return NavigationStack { PlanView(plan: plan, store: store) }
}
