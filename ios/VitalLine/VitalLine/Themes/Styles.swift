import SwiftUI

// Shared building blocks for every screen, in the VitalLine palette (Theme.swift).

extension View {
    // Rounded panel in the Surface color.
    func card() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // Midnight background plus matching nav bar and tab bar.
    func vitalScreen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.midnight)
            .toolbarBackground(Color.midnight, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.textPrimary)
            .padding(.top, 8)
    }
}

// Big cyan button: "Start Response", "Start Navigation", "Yes".
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.midnight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// Outlined button: "No".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.brandPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandPrimary, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// The demo twist. Drop it into any screen: ElevatorToggle()
struct ElevatorToggle: View {
    @Environment(PlanStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Toggle(isOn: $store.elevatorOut) {
            Label("Elevator out of service", systemImage: "arrow.up.arrow.down.square")
                .foregroundStyle(.textPrimary)
        }
        .tint(.critical)
        .card()
        .sensoryFeedback(.impact, trigger: store.elevatorOut)
        .onChange(of: store.elevatorOut) {
            Task { await store.load() }
        }
    }
}

func minutesText(_ seconds: Int) -> String {
    String(format: "%.1f", Double(seconds) / 60.0)
}
