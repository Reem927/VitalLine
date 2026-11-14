import SwiftUI

// Summary of the incoming call. Reusable: Dispatch home and History rows.
struct DispatchCard: View {
    let plan: Plan

    private var etaText: String {
        if let eta = plan.outdoor.etaMinutes { return "\(eta) min" }
        return "Calculating…"
    }

    private var priority: String { plan.dispatch.priority ?? "Unknown" }

    private var priorityColor: Color {
        switch priority.lowercased() {
        case "high": return .critical
        case "medium": return .caution
        default: return .textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cross.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.critical)
                Text(plan.dispatch.complaint)
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
            }

            Divider().overlay(Color.textSecondary.opacity(0.3))

            DispatchInfoRow(icon: "building.2",
                            text: "\(plan.dispatch.address) · Floor \(plan.dispatch.floor), Unit \(plan.dispatch.unit)")
            DispatchInfoRow(icon: "clock", text: "ETA: \(etaText)")

            HStack(spacing: 8) {
                DispatchInfoRow(icon: "exclamationmark.circle", text: "Priority:")
                Text(priority)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(priorityColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(priorityColor)
            }
        }
        .card()
    }
}

// Private so it can't clash with a shared InfoRow component.
private struct DispatchInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(.textPrimary)
        } icon: {
            Image(systemName: icon).foregroundStyle(.textSecondary)
        }
        .font(.subheadline)
    }
}
