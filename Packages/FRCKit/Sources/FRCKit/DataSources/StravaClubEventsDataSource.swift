import Foundation

/// Live data: the signed-in athlete's clubs and their upcoming group events.
///
/// Cost per full load is 1 + (number of clubs) requests. Admins, attendees
/// and route details are fetched only when an event is opened.
public final class StravaClubEventsDataSource: ClubEventsDataSource {
    private let client: StravaAPIClient
    private let maxConcurrentClubRequests: Int
    private let adminsCache = MemoCache<Int, [StravaAthlete]>()
    private let routeCache = MemoCache<StravaID, StravaRoute>()

    public init(client: StravaAPIClient, maxConcurrentClubRequests: Int = 4) {
        self.client = client
        self.maxConcurrentClubRequests = max(maxConcurrentClubRequests, 1)
    }

    public func loadClubEvents() async throws -> ClubEventsSnapshot {
        let clubs = try await client.athleteClubs()
        let results = await fetchEvents(for: clubs)

        var events: [ClubEvent] = []
        var failures: [ClubLoadFailure] = []
        var errors: [Error] = []
        for (club, result) in results {
            switch result {
            case .success(let clubEvents):
                events += clubEvents.map { ClubEvent(event: $0, club: club) }
            case .failure(let error):
                errors.append(error)
                failures.append(ClubLoadFailure(club: club, message: error.localizedDescription))
            }
        }

        // Session-level problems should surface as errors, not as an empty map.
        if let authError = errors.first(where: { ($0 as? StravaAPIError) == .unauthorized || ($0 as? StravaAPIError) == .notSignedIn }) {
            throw authError
        }
        if !clubs.isEmpty, failures.count == clubs.count, let firstError = errors.first {
            throw firstError
        }

        return ClubEventsSnapshot(
            clubs: clubs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            events: events,
            failures: failures,
            loadedAt: Date()
        )
    }

    public func clubAdmins(clubID: Int) async throws -> [StravaAthlete] {
        let client = client
        return try await adminsCache.value(for: clubID) {
            try await client.clubAdmins(clubID: clubID)
        }
    }

    public func attendees(eventID: StravaID) async throws -> [StravaAthlete] {
        // Not cached: attendance changes as people join.
        try await client.groupEventAthletes(eventID: eventID)
    }

    public func routeDetails(id: StravaID) async throws -> StravaRoute {
        let client = client
        return try await routeCache.value(for: id) {
            try await client.route(id: id)
        }
    }

    /// Fetches each club's events with bounded concurrency, keeping per-club failures.
    private func fetchEvents(for clubs: [StravaClub]) async -> [(StravaClub, Result<[StravaGroupEvent], Error>)] {
        let client = client
        let maxConcurrent = maxConcurrentClubRequests
        return await withTaskGroup(of: (Int, Result<[StravaGroupEvent], Error>).self) { group in
            var results: [Int: Result<[StravaGroupEvent], Error>] = [:]
            var nextIndex = 0
            var inFlight = 0

            while nextIndex < clubs.count || inFlight > 0 {
                while inFlight < maxConcurrent, nextIndex < clubs.count {
                    let index = nextIndex
                    let clubID = clubs[index].id
                    group.addTask {
                        do {
                            let events = try await client.upcomingGroupEvents(clubID: clubID)
                            return (index, Result.success(events))
                        } catch {
                            return (index, Result.failure(error))
                        }
                    }
                    nextIndex += 1
                    inFlight += 1
                }
                guard let finished = await group.next() else { break }
                results[finished.0] = finished.1
                inFlight -= 1
            }

            return clubs.indices.compactMap { index in
                results[index].map { (clubs[index], $0) }
            }
        }
    }
}
