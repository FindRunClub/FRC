import FRCKit
import Foundation
import Observation

/// Top-level app state: Strava sign-in plus the events store it feeds.
@MainActor
@Observable
final class AppModel {
    let auth: StravaAuthController
    let events = EventsStore()
    private(set) var forceDemoData: Bool

    private static let forceDemoDataKey = "forceDemoData"

    init(config: AppConfig = .current) {
        auth = StravaAuthController(config: config)
        forceDemoData = UserDefaults.standard.bool(forKey: Self.forceDemoDataKey)
    }

    /// Demo data shows until Strava is connected, or when forced for QA.
    var isUsingDemoData: Bool {
        !auth.isSignedIn || forceDemoData
    }

    struct DataSourceKey: Equatable {
        let signedIn: Bool
        let forceDemo: Bool
    }

    var dataSourceKey: DataSourceKey {
        DataSourceKey(signedIn: auth.isSignedIn, forceDemo: forceDemoData)
    }

    func setForceDemoData(_ enabled: Bool) {
        forceDemoData = enabled
        UserDefaults.standard.set(enabled, forKey: Self.forceDemoDataKey)
    }

    func activateDataSource() async {
        if let session = auth.session, !isUsingDemoData {
            let client = StravaAPIClient(tokens: session)
            events.use(StravaClubEventsDataSource(client: client), isDemo: false)
        } else {
            events.use(DemoClubEventsDataSource(), isDemo: true)
        }
        await events.load()
        if events.needsReconnect {
            await auth.handleSessionEnded()
        }
    }
}
