import FRCKit
import Foundation
import Observation

/// Top-level app state: Strava sign-in, the area's club directory, and the
/// events store they feed.
@MainActor
@Observable
final class AppModel {
    let auth: StravaAuthController
    let directory: ClubDirectoryStore
    let events = EventsStore()
    let savedClubs = SavedClubs()
    private(set) var forceDemoData: Bool

    private static let forceDemoDataKey = "forceDemoData"

    init(config: AppConfig = .current) {
        auth = StravaAuthController(config: config)
        directory = ClubDirectoryStore(remoteURL: config.clubDirectoryURL)
        forceDemoData = UserDefaults.standard.bool(forKey: Self.forceDemoDataKey)
    }

    /// Demo data shows until Strava is connected, or when forced for QA.
    var isUsingDemoData: Bool {
        !auth.isSignedIn || forceDemoData
    }

    struct DataSourceKey: Equatable {
        let signedIn: Bool
        let forceDemo: Bool
        /// Reload when clubs are added to or removed from the area directory.
        let directory: String
    }

    var dataSourceKey: DataSourceKey {
        DataSourceKey(signedIn: auth.isSignedIn, forceDemo: forceDemoData, directory: directory.revision)
    }

    func setForceDemoData(_ enabled: Bool) {
        forceDemoData = enabled
        UserDefaults.standard.set(enabled, forKey: Self.forceDemoDataKey)
    }

    func activateDataSource() async {
        if let session = auth.session, !isUsingDemoData {
            let client = StravaAPIClient(tokens: session)
            events.use(StravaClubEventsDataSource(client: client, directoryClubs: directory.clubs), isDemo: false)
        } else {
            events.use(DemoClubEventsDataSource(), isDemo: true)
        }
        await events.load()
        if events.needsReconnect {
            await auth.handleSessionEnded()
        }
    }

    enum AddClubError: LocalizedError {
        case notALink
        case notSignedIn
        case notFound

        var errorDescription: String? {
            switch self {
            case .notALink:
                return "Paste a Strava club link, like strava.com/clubs/123456."
            case .notSignedIn:
                return "Connect Strava first; FRC looks the club up with your account."
            case .notFound:
                return "Strava couldn't find that club. Try the link with the club's number (strava.com/clubs/123456)."
            }
        }
    }

    /// Adds a club to the runner's area from a pasted Strava link or ID.
    @discardableResult
    func addClub(from text: String) async throws -> StravaClub {
        guard let link = StravaClubLink(text) else { throw AddClubError.notALink }
        guard let session = auth.session, auth.isSignedIn else { throw AddClubError.notSignedIn }
        do {
            let club = try await StravaAPIClient(tokens: session).club(link)
            directory.add(club)
            return club
        } catch StravaAPIError.notFound {
            throw AddClubError.notFound
        }
    }
}
