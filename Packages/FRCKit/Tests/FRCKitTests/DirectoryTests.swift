import XCTest
@testable import FRCKit

final class UpcomingDayTests: XCTestCase {
    private let nashville = TimeZone(identifier: "America/Chicago")!
    private let club = StravaClub(id: 1, name: "Five Points Run Club")

    private func date(_ iso: String) -> Date {
        StravaDateParser.parse(iso)!
    }

    /// A weekly event with the given upcoming dates (as Strava lists them).
    private func weekly(_ id: String, _ dates: [String]) -> ClubEvent {
        ClubEvent(
            event: StravaGroupEvent(
                id: StravaID(id), title: id,
                upcomingOccurrences: dates.map { date($0) },
                timeZoneIdentifier: nashville.identifier
            ),
            club: club
        )
    }

    private func schedule(now: String, _ events: [ClubEvent]) -> WeekSchedule {
        WeekSchedule(events: events, now: date(now), timeZone: nashville, dayCount: 8)
    }

    func testPastWeekdaysMeanTheUpcomingOne() {
        // Tuesday 6 PM runs on Sep 29 and Oct 6, 2026 (Central time).
        let tuesdayRun = weekly("tue", ["2026-09-29T23:00:00Z", "2026-10-06T23:00:00Z"])

        // On Wednesday, Tuesday means next Tuesday, not yesterday.
        let wednesday = schedule(now: "2026-09-30T15:00:00Z", [tuesdayRun])
        XCTAssertEqual(wednesday.upcomingOccurrences(on: .tuesday).map(\.day), [LocalDay(year: 2026, month: 10, day: 6)])

        // Same on Friday.
        let friday = schedule(now: "2026-10-02T15:00:00Z", [tuesdayRun])
        XCTAssertEqual(friday.upcomingOccurrences(on: .tuesday).map(\.day), [LocalDay(year: 2026, month: 10, day: 6)])
    }

    func testTodayShowsLaterRunsAndRollsEarlierOnesToNextWeek() {
        // It's Tuesday Sep 29 at 3 PM Central.
        let morning = weekly("morning", ["2026-10-06T11:00:00Z"]) // 6 AM run: today's already happened
        let evening = weekly("evening", ["2026-09-29T23:00:00Z", "2026-10-06T23:00:00Z"]) // 6 PM run
        let today = schedule(now: "2026-09-29T20:00:00Z", [morning, evening])

        let tuesday = today.upcomingOccurrences(on: .tuesday)
        XCTAssertEqual(tuesday.map(\.event.id.rawValue), ["evening", "morning"])
        XCTAssertEqual(tuesday.map(\.day), [LocalDay(year: 2026, month: 9, day: 29), LocalDay(year: 2026, month: 10, day: 6)])
        XCTAssertEqual(tuesday.count, 2, "Each event appears once, at its next run")
    }
}

final class DirectoryTests: XCTestCase {
    func testClubLinksFromWhateverRunnersPaste() {
        XCTAssertEqual(StravaClubLink("https://www.strava.com/clubs/123456"), .id(123456))
        XCTAssertEqual(StravaClubLink("strava.com/clubs/123456/group_events/99"), .id(123456))
        XCTAssertEqual(StravaClubLink(" 123456 "), .id(123456))
        XCTAssertEqual(StravaClubLink("https://www.strava.com/clubs/five-points-rc"), .slug("five-points-rc"))
        XCTAssertNil(StravaClubLink("https://example.com/clubs/123"))
        XCTAssertNil(StravaClubLink("https://www.strava.com/athletes/42"))
        XCTAssertNil(StravaClubLink("not a link"))
    }

    func testDirectoryDecodingAndNearestArea() throws {
        let json = #"""
        {
          "areas": [
            { "id": "nashville", "name": "Nashville, TN", "latitude": 36.16, "longitude": -86.78,
              "clubs": [ { "id": 111, "name": "Club A" }, { "id": 222, "name": "Club B", "city": "Nashville", "state": "TN" } ] },
            { "id": "austin", "name": "Austin, TX", "latitude": 30.27, "longitude": -97.74, "clubs": [] }
          ]
        }
        """#
        let directory = try ClubDirectory.decode(Data(json.utf8))
        XCTAssertEqual(directory.areas.map(\.id), ["nashville", "austin"])
        XCTAssertEqual(directory.areas[0].clubs.map(\.club.name), ["Club A", "Club B"])
        XCTAssertEqual(directory.nearestArea(to: Coordinate(latitude: 30.3, longitude: -97.7))?.id, "austin")
        XCTAssertEqual(directory.nearestArea(to: nil)?.id, "nashville")
    }

    func testLiveSourceLoadsJoinedAndDirectoryClubs() async throws {
        let transport = MockTransport { request in
            switch request.url?.path {
            case "/api/v3/athlete/clubs":
                return (200, #"[{"id": 1, "name": "My Club"}]"#)
            case "/api/v3/clubs/1/group_events", "/api/v3/clubs/2/group_events":
                return (200, "[]")
            case "/api/v3/clubs/3/group_events":
                return (403, #"{"message":"Forbidden"}"#)
            default:
                return (404, "{}")
            }
        }
        let storage = InMemoryTokenStorage(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3_600)))
        let session = StravaSession(
            credentials: StravaAppCredentials(clientID: "1", clientSecret: "s", redirectURI: "findrunclub://localhost"),
            storage: storage,
            transport: transport
        )
        let source = StravaClubEventsDataSource(
            client: StravaAPIClient(transport: transport, tokens: session),
            directoryClubs: [
                StravaClub(id: 1, name: "My Club (listed too)"),
                StravaClub(id: 2, name: "Open Club"),
                StravaClub(id: 3, name: "Private Club"),
            ]
        )

        let snapshot = try await source.loadClubEvents()

        XCTAssertEqual(snapshot.clubs.map(\.id).sorted(), [1, 2, 3], "The joined club isn't loaded twice")
        XCTAssertEqual(snapshot.clubs.first { $0.id == 1 }?.isMember, true)
        XCTAssertEqual(snapshot.clubs.first { $0.id == 2 }?.isMember, false)
        XCTAssertEqual(snapshot.failures.map(\.club.id), [3])
        XCTAssertEqual(snapshot.failures.first?.message, "Strava only shows this club's events to its members.")
    }

    func testMyClubsOnlyFilter() {
        let start = Date()
        func run(_ club: StravaClub) -> ClubRun {
            ClubRun.group([EventOccurrence(
                event: StravaGroupEvent(id: StravaID("\(club.id)"), title: "Run", upcomingOccurrences: [start]),
                club: club,
                start: start
            )])[0]
        }
        let mine = run(StravaClub(id: 1, name: "Mine", isMember: true))
        let other = run(StravaClub(id: 2, name: "Other"))
        let filter = RunFilter(myClubsOnly: true)
        XCTAssertTrue(filter.includes(mine))
        XCTAssertFalse(filter.includes(other))
        XCTAssertTrue(RunFilter().includes(other))
    }
}
