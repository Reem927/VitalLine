//
//  ContentView.swift
//  VitalLine
//
//  Created by mac on 14/11/2026.
//

import SwiftUI

// Root of the app: three tabs that all share one PlanStore.
struct ContentView: View {
    @State private var store = PlanStore()

    var body: some View {
        TabView {
            PlanTab(title: "Route", store: store) { plan in
                RouteTab(plan: plan)
            }
            .tabItem { Label("Route", systemImage: "map") }

            PlanTab(title: "Floor \(store.plan?.indoor.floor ?? 0)", store: store) { plan in
                FloorTab(plan: plan, store: store)
            }
            .tabItem { Label("Floor", systemImage: "square.grid.3x3") }

            PlanTab(title: "Brief", store: store) { plan in
                BriefTab(plan: plan)
            }
            .tabItem { Label("Brief", systemImage: "text.bubble") }
        }
        .task { await store.load() }
        .preferredColorScheme(.dark)   // system text and controls turn light
        .tint(.brandPrimary)           // tab bar, buttons, links use your cyan
    }
}

#Preview {
    ContentView()
}
