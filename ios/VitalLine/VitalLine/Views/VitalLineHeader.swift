import SwiftUI

// The VitalLine logo, centered. Needs "VitalLineLogo" in Assets.xcassets.
struct VitalLineHeader: View {
    var height: CGFloat = 40

    var body: some View {
        Image("VitalLineLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("VitalLine")
            .padding(.vertical, 8)
    }
}

#Preview {
    VitalLineHeader()
        .padding()
        .background(Color.midnight)
}
