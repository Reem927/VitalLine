import SwiftUI

// Screen 2: Route Preview (Outdoor). Start, end, map and drive time.
struct RoutePreviewView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let dispatch = store.dispatch, let outdoor = store.outdoor {
                content(dispatch, outdoor)
            } else if let message = store.errorMessage, !store.isPlanning {
                VStack(spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.critical)
                    Button("Retry") { Task { await store.startResponse() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding()
            } else {
                locating
            }
        }
        .navigationTitle("Route Preview")
        .navigationBarTitleDisplayMode(.inline)
        .vitalScreen()
    }

    // Shown for the few seconds before location-resolver and outdoor-route finish.
    private var locating: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Locating building…")
                .font(.headline)
                .foregroundStyle(.textPrimary)
            ForEach(store.tasks.filter { ["location", "outdoor"].contains($0.id) }) { task in
                HStack(spacing: 10) {
                    if task.isDone {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.success)
                    } else {
                        ProgressView().tint(.brandPrimary)
                    }
                    Text(task.detail ?? task.title).foregroundStyle(.textPrimary)
                }
            }
        }
        .card()
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func content(_ dispatch: DispatchInfo, _ outdoor: Outdoor) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // From / To
                VStack(alignment: .leading, spacing: 12) {
                    endpoint(label: "From", text: "Current Location",
                             icon: "location.circle.fill", color: .brandPrimary)
                    Divider().overlay(Color.textSecondary.opacity(0.3))
                    endpoint(label: "To", text: dispatch.address,
                             icon: "mappin.circle.fill", color: .critical)
                }
                .card()

                RouteMapView(outdoor: outdoor)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Drive time and distance
                HStack(spacing: 10) {
                    Image(systemName: "car.fill").foregroundStyle(.brandPrimary)
                    Text(driveText(outdoor))
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                    Spacer()
                }
                .card()

                if !outdoor.flags.isEmpty {
                    FlagsList(flags: outdoor.flags)
                        .card()
                }

                Button("Start Navigation") {
                    router.push(.liveNavigation)   // agents keep working; progress shows there
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

    private func driveText(_ outdoor: Outdoor) -> String {
        guard let eta = outdoor.etaMinutes else { return "Drive time unknown" }
        if let km = outdoor.distanceKm {
            return "\(eta) min (\(String(format: "%.1f", km)) km)"
        }
        return "\(eta) min"
    }
}
