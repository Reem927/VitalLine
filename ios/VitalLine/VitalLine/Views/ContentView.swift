//
//  ContentView.swift
//  VitalLine
//
//  Created by mac on 14/11/2026.
//

import SwiftUI

// Root of the app. Creates the shared stores once and hands them
// to every screen through the environment.
struct ContentView: View {
    @State private var store = PlanStore()
    @State private var router = AppRouter()
    @State private var history = HistoryStore()

    var body: some View {
        Tabs()
            .environment(store)
            .environment(router)
            .environment(history)
            .preferredColorScheme(.dark)
            .tint(.brandPrimary)
            .task { await store.load() }
    }
}

#Preview {
    ContentView()
}
