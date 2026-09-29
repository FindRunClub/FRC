import SwiftUI
import UIKit

@main
struct FindRunClubApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.ink)
                // The FRC palettes are light-only for now.
                .preferredColorScheme(.light)
        }
    }
}

/// Picks the data source (Strava vs. sample data) whenever sign-in state
/// changes, and keeps "today" current when the app returns to the foreground.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MapScreen()
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

/// The map and club screens hide the navigation bar for their own buttons;
/// this keeps the edge swipe-back gesture working without it.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
