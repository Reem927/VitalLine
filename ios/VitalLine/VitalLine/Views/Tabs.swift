import SwiftUI

// Bottom tab bar: Dispatch / History / Settings.
// The Dispatch tab is a stack: Dispatch -> Route Preview -> Live Nav
// -> Indoor Plan -> Completed. Screens move forward with router.push(...).
struct Tabs: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.path) {
                DispatchView()
                    .navigationDestination(for: AppScreen.self) { screen in
                        switch screen {
                        case .routePreview:   RoutePreviewView()
                        case .liveNavigation: LiveNavigationView()
                        case .indoorPlan:     IndoorPlanView()
                        case .arNavigation:   ARNavigationView()
                        case .completed:      CompletionView()
                        }
                    }
            }
            .tabItem { Label("Dispatch", systemImage: "cross.case.fill") }
            .tag(AppTab.dispatch)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
    }
}
