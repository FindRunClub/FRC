import XCTest
@testable import FRCKit

final class ScheduleTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    /// Tuesday 2026-09-29, 10:00 in New York.
    private let now = Date(timeIntervalSince1970: 1_790_690_400)
    private let club = StravaClub(id: 1, name: "Test Club")

    private func date(_ iso: String) -> Date {
        StravaDateParser.parse(iso)!
    }

    private func event(_ id: String, zone: TimeZone, type: String = "Run", at dates: [String], coordinate: Coordinate? = nil) -> ClubEvent {
        ClubEvent(
            event: StravaGroupEvent(
                id: StravaID(id),
                title: id,
                activityType: type,
                upcomingOccurrences: dates.map { date($0) },
                timeZoneIdentifier: zone.identifier,
                startCoordinate: coordinate
            ),
            club: club
        )
    }

    func testWeekStartsTodayAndSpansSevenDays() {
        let schedule = WeekSchedule(events: [], now: now, timeZone: newYork)
        XCTAssertEqual(schedule.days.count, 7)
        XCTAssertEqual(schedule.days.first, LocalDay(year: 2026, month: 9, day: 29))
        XCTAssertEqual(schedule.days.last, LocalDay(year: 2026, month: 10, day: 5))
        XCTAssertEqual(schedule.days.first?.weekday, 3, "2026-09-29 is a Tuesday")
    }

    func testBucketsOccurrencesByTheEventsLocalDay() {
        let events = [
            event("nyc", zone: newYork, at: [
                "2026-09-29T12:00:00Z", // 8:00 AM, two hours ago: over, hidden
                "2026-09-29T13:30:00Z", // 9:30 AM, started 30 min ago: still shown
                "2026-09-29T22:30:00Z", // 6:30 PM Tuesday
                "2026-09-29T22:30:00Z", // duplicate, ignored
                "2026-09-30T10:00:00Z", // 6:00 AM Wednesday
                "2026-10-06T10:00:00Z", // next Tuesday: outside the 7-day window
            ]),
            // 9:00 PM Tuesday in Los Angeles is already Wednesday in UTC and New York,
            // but the run happens on Tuesday where it takes place.
            event("la", zone: losAngeles, at: ["2026-09-30T04:00:00Z"]),
            event("ride", zone: newYork, type: "Ride", at: ["2026-09-29T23:00:00Z"]),
        ]
        let schedule = WeekSchedule(events: events, now: now, timeZone: newYork)

        let tuesday = schedule.occurrences(on: LocalDay(year: 2026, month: 9, day: 29))
        XCTAssertEqual(tuesday.map(\.event.id.rawValue), ["nyc", "nyc", "ride", "la"])
        XCTAssertEqual(tuesday.map(\.start), [
            date("2026-09-29T13:30:00Z"), date("2026-09-29T22:30:00Z"), date("2026-09-29T23:00:00Z"), date("2026-09-30T04:00:00Z"),
        ])

        let wednesday = schedule.occurrences(on: LocalDay(year: 2026, month: 9, day: 30))
        XCTAssertEqual(wednesday.map(\.start), [date("2026-09-30T10:00:00Z")])
        XCTAssertEqual(schedule.allOccurrences.count, 5)

        let filtered = tuesday.filter(EventFilter(runsOnly: true).includes)
        XCTAssertEqual(filtered.map(\.event.id.rawValue), ["nyc", "nyc", "la"])
        XCTAssertTrue(tuesday.filter(EventFilter(runsOnly: false, hiddenClubIDs: [club.id]).includes).isEmpty)
    }

    func testTimeZoneNoteOnlyForOtherTimeZones() {
        let occurrence = EventOccurrence(
            event: StravaGroupEvent(id: "1", title: "t", upcomingOccurrences: [], timeZoneIdentifier: losAngeles.identifier),
            club: club,
            start: date("2026-09-30T04:00:00Z")
        )
        XCTAssertNotNil(occurrence.timeZoneNote(viewerTimeZone: newYork), "e.g. \"PDT\"")
        XCTAssertNil(occurrence.timeZoneNote(viewerTimeZone: losAngeles))
        XCTAssertEqual(occurrence.day, LocalDay(year: 2026, month: 9, day: 29))
    }

    func testClustersGroupRunsLeavingFromTheSameSpot() {
        let pier = Coordinate(latitude: 40.74660, longitude: -74.00800)
        let nearlyThePier = Coordinate(latitude: 40.746601, longitude: -74.008002)
        let park = Coordinate(latitude: 40.67400, longitude: -73.97010)
        let events = [
            event("evening", zone: newYork, at: ["2026-09-29T22:30:00Z"], coordinate: pier),
            event("morning", zone: newYork, at: ["2026-09-29T13:30:00Z"], coordinate: nearlyThePier),
            event("park", zone: newYork, at: ["2026-09-29T23:00:00Z"], coordinate: park),
            event("nowhere", zone: newYork, at: ["2026-09-29T23:30:00Z"]),
        ]
        let occurrences = WeekSchedule(events: events, now: now, timeZone: newYork).occurrences(on: LocalDay(year: 2026, month: 9, day: 29))
        let clusters = LocationCluster.clusters(for: occurrences)

        XCTAssertEqual(clusters.count, 2, "Occurrences without coordinates are left off the map")
        let pierCluster = try? XCTUnwrap(clusters.first { $0.occurrences.count == 2 })
        XCTAssertEqual(pierCluster?.occurrences.map(\.event.id.rawValue), ["morning", "evening"])
    }

    func testLocalDayArithmetic() {
        let day = LocalDay(year: 2026, month: 12, day: 31)
        XCTAssertEqual(day.adding(days: 1), LocalDay(year: 2027, month: 1, day: 1))
        XCTAssertEqual(day.adding(days: -365), LocalDay(year: 2025, month: 12, day: 31))
        XCTAssertLessThan(day, day.adding(days: 1))
        XCTAssertEqual(day.description, "2026-12-31")
        XCTAssertEqual(LocalDay(date("2026-03-08T07:30:00Z"), timeZone: newYork), LocalDay(year: 2026, month: 3, day: 8))
    }

    func testCoordinateBounds() throws {
        let bounds = try XCTUnwrap(CoordinateBounds([
            Coordinate(latitude: 40.70, longitude: -74.01),
            Coordinate(latitude: 40.80, longitude: -73.95),
        ]))
        XCTAssertEqual(bounds.center.latitude, 40.75, accuracy: 1e-9)
        XCTAssertEqual(bounds.center.longitude, -73.98, accuracy: 1e-9)
        XCTAssertEqual(bounds.paddedSpan().latitudeDelta, 0.14, accuracy: 1e-9)

        let single = try XCTUnwrap(CoordinateBounds([Coordinate(latitude: 1, longitude: 2)]))
        XCTAssertEqual(single.paddedSpan().longitudeDelta, 0.02, "A lone pin gets a sensible minimum zoom")
        XCTAssertNil(CoordinateBounds([]))
    }

    func testPolylineMatchesGoogleReferenceAndRoundTrips() {
        let decoded = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(decoded, [
            Coordinate(latitude: 38.5, longitude: -120.2),
            Coordinate(latitude: 40.7, longitude: -120.95),
            Coordinate(latitude: 43.252, longitude: -126.453),
        ])
        XCTAssertEqual(Polyline.encode(decoded), "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertTrue(Polyline.decode("").isEmpty)
        XCTAssertEqual(Polyline.decode("_p~iF~ps|U_ulL").count, 1, "A truncated tail is ignored")
    }

    func testDemoDataFillsEveryDayOfTheWeek() async throws {
        // Tuesday 00:30 in New York, so all of Tuesday's demo runs are still ahead.
        let reference = date("2026-09-29T04:30:00Z")
        let source = DemoClubEventsDataSource(now: { reference }, latencySeconds: 0)
        let snapshot = try await source.loadClubEvents()
        XCTAssertEqual(snapshot.clubs.count, 8)

        let schedule = WeekSchedule(events: snapshot.events, now: reference, timeZone: newYork)
        let runsOnly = EventFilter(runsOnly: true)
        for day in schedule.days {
            let runs = schedule.occurrences(on: day).filter(runsOnly.includes)
            XCTAssertFalse(runs.isEmpty, "Expected demo runs on \(day)")
        }

        // Saturday at Chelsea Piers stacks the club long run with a bike ride.
        let saturday = schedule.occurrences(on: LocalDay(year: 2026, month: 10, day: 3))
        XCTAssertTrue(saturday.contains { !$0.event.isRun })
        XCTAssertTrue(LocationCluster.clusters(for: saturday).contains { $0.occurrences.count == 2 })

        let sunset5K = try XCTUnwrap(snapshot.events.first { $0.event.id.rawValue == "demo-102" })
        XCTAssertTrue(sunset5K.event.joined)
        let routeID = try XCTUnwrap(sunset5K.event.route?.id)
        let route = try await source.routeDetails(id: routeID)
        XCTAssertEqual(route.distance ?? 0, 5_000, accuracy: 500)
        XCTAssertGreaterThan(route.coordinates.count, 5)

        let attendees = try await source.attendees(eventID: sunset5K.event.id)
        XCTAssertEqual(attendees.count, 38)
        let admins = try await source.clubAdmins(clubID: sunset5K.club.id)
        XCTAssertFalse(admins.isEmpty)
    }
}
