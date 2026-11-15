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
    @State private var auth = AuthStore()

    var body: some View {
        Group {
            if auth.isSignedIn {
                Tabs().task { await store.load() }
            } else {
                LoginView()
            }
        }
        .environment(store)
        .environment(router)
        .environment(history)
        .environment(auth)
        .preferredColorScheme(.dark)
        .tint(.brandPrimary)
        .task { await auth.checkBackend() }
        // Under memory pressure, drop the shared scans; they reload from the phone's cache.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            ScanMesh.releaseAll()
        }
    }
}

#Preview {
    ContentView()
}
