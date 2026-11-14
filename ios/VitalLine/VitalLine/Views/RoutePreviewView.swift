import SwiftUI

// Screen 2: Route Preview (Outdoor). Start, end, map and drive time.
struct RoutePreviewView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let plan = store.plan {
                content(plan)
            } else {
                ProgressView().tint(.brandPrimary)
            }
        }
        .navigationTitle("Route Preview")
        .navigationBarTitleDisplayMode(.inline)
        .vitalScreen()
    }

    private func content(_ plan: Plan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // From / To
                VStack(alignment: .leading, spacing: 12) {
                    endpoint(label: "From", text: "Current Location",
                             icon: "location.circle.fill", color: .brandPrimary)
                    Divider().overlay(Color.textSecondary.opacity(0.3))
                    endpoint(label: "To", text: plan.dispatch.address,
                             icon: "mappin.circle.fill", color: .critical)
                }
                .card()

                RouteMapView(outdoor: plan.outdoor)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Drive time and distance
                HStack(spacing: 10) {
                    Image(systemName: "car.fill").foregroundStyle(.brandPrimary)
                    Text(driveText(plan))
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                    Spacer()
                }
                .card()

                if !plan.outdoor.flags.isEmpty {
                    FlagsList(flags: plan.outdoor.flags)
                        .card()
                }

                Button("Start Navigation") {
                    Task { await store.runAgents() }   // agents start planning the indoor leg
                    router.push(.liveNavigation)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
            }
            .padding()
        }
    }

    private func endpoint(label: String, text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.textSecondary)
                Text(text).foregroundStyle(.textPrimary)
            }
        }
    }

    private func driveText(_ plan: Plan) -> String {
        guard let eta = plan.outdoor.etaMinutes else { return "Drive time unknown" }
        if let km = plan.outdoor.distanceKm {
            return "\(eta) min (\(String(format: "%.1f", km)) km)"
        }
        return "\(eta) min"
    }
}
