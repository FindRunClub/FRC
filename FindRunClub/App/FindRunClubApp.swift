import SwiftUI

@main
struct FindRunClubApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.stravaOrange)
        }
    }
}

/// Picks the data source (Strava vs. demo) whenever sign-in state changes,
/// and keeps "today" current when the app returns to the foreground.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        EventsHomeView()
            .task(id: model.dataSourceKey) {
                await model.activateDataSource()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.events.rollOverToTodayIfNeeded()
                }
            }
    }
}
