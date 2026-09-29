import Foundation

/// Everything the events screens need, in one load.
public struct ClubEventsSnapshot: Sendable {
    public var clubs: [StravaClub]
    public var events: [ClubEvent]
    /// Clubs whose events couldn't be loaded (shown as a warning, not a failure).
    public var failures: [ClubLoadFailure]
    /// Weekly turnout by event, where the source knows it (Strava doesn't expose it).
    public var turnout: [StravaID: TurnoutHistory]
    public var loadedAt: Date

    public init(
        clubs: [StravaClub],
        events: [ClubEvent],
        failures: [ClubLoadFailure] = [],
        turnout: [StravaID: TurnoutHistory] = [:],
        loadedAt: Date = Date()
    ) {
        self.clubs = clubs
        self.events = events
        self.failures = failures
        self.turnout = turnout
        self.loadedAt = loadedAt
    }
}

public struct ClubLoadFailure: Hashable, Sendable {
    public let club: StravaClub
    public let message: String

    public init(club: StravaClub, message: String) {
        self.club = club
        self.message = message
    }
}

/// Where club events come from. The app ships two: live Strava data and a
/// demo set. A future FRC backend would be a third conformance.
public protocol ClubEventsDataSource: Sendable {
    /// Clubs plus their upcoming events: the one call made on launch/refresh.
    func loadClubEvents() async throws -> ClubEventsSnapshot
    /// Loaded lazily when an event's details are opened.
    func clubAdmins(clubID: Int) async throws -> [StravaAthlete]
    func attendees(eventID: StravaID) async throws -> [StravaAthlete]
    func routeDetails(id: StravaID) async throws -> StravaRoute
}

/// Remembers results for the lifetime of a data source (e.g. routes and
/// admins, which rarely change) so reopening an event costs no API calls.
actor MemoCache<Key: Hashable & Sendable, Value: Sendable> {
    private var values: [Key: Value] = [:]

    func value(for key: Key, load: @Sendable () async throws -> Value) async throws -> Value {
        if let cached = values[key] {
            return cached
        }
        let loaded = try await load()
        values[key] = loaded
        return loaded
    }
}
