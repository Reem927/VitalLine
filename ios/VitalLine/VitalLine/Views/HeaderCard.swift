import SwiftUI

struct HeaderCard: View {
    let plan: Plan

    private var isStairChair: Bool { plan.indoor.mode == "stair_chair" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("VitalLineLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 32)
                    .accessibilityLabel("VitalLine")
                    .padding(.bottom, 4)
            
            Text(plan.dispatch.complaint)
                .font(.headline)
            Text("\(plan.dispatch.address) · Floor \(plan.dispatch.floor), Unit \(plan.dispatch.unit)")
                .font(.subheadline)
                .foregroundStyle(.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(minutesText(plan.time.minSeconds))–\(minutesText(plan.time.maxSeconds)) min")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("door to patient")
                    .foregroundStyle(.textSecondary)
            }

            HStack {
                Label(isStairChair ? "Stair chair" : "Stretcher",
                      systemImage: isStairChair ? "figure.stairs" : "bed.double.fill")
                    .font(.subheadline.bold())
                Spacer()
                VerifiedBadge(verified: plan.verification.verified,
                              by: plan.verification.verifiedBy)
            }
        }
        .card()
        .animation(.default, value: plan.time.maxSeconds)
    }
}

struct VerifiedBadge: View {
    let verified: Bool
    var by: String? = nil          // nil (mock) or "wolfram" -> Wolfram; otherwise local math

    private var verifiedText: String {
        by == nil || by == "wolfram" ? "Verified by Wolfram" : "Math checked"
    }

    var body: some View {
        let color: Color = verified ? .success : .caution
        Label(verified ? verifiedText : "Not verified",
              systemImage: verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
