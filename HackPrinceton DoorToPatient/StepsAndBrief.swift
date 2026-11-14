import SwiftUI

struct StepsView: View {
    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(step.id)")
                        .font(.caption.bold())
                        .frame(width: 26, height: 26)
                        .background(Color.blue.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.text)
                        Text("\(step.secondsMin)–\(step.secondsMax) s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct BriefView: View {
    let lines: [String]
    let verification: Verification

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text("\(index + 1). \(line)")
            }

            DisclosureGroup("Why? Show the math") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verification.expression)
                        .font(.system(.footnote, design: .monospaced))
                    Text("= \(verification.result)")
                        .font(.system(.footnote, design: .monospaced).bold())
                    VerifiedBadge(verified: verification.verified)
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
