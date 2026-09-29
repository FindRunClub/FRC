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

        let runs = ClubRun.group(tuesday)
        XCTAssertEqual(runs.filter { RunFilter(runsOnly: true).includes($0) }.map(\.primary.event.id.rawValue), ["nyc", "nyc", "la"])
        XCTAssertTrue(runs.filter { RunFilter(runsOnly: false, hiddenClubIDs: [club.id]).includes($0) }.isEmpty)
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
        let clusters = LocationCluster.clusters(for: ClubRun.group(occurrences))

        XCTAssertEqual(clusters.count, 2, "Runs without coordinates are left off the map")
        let pierCluster = clusters.first { $0.runs.count == 2 }
        XCTAssertEqual(pierCluster?.runs.map(\.primary.event.id.rawValue), ["morning", "evening"])
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
        // Tuesday 00:30 in Nashville, so all of Tuesday's demo runs are still ahead.
        let reference = date("2026-09-29T05:30:00Z")
        let nashville = TimeZone(identifier: "America/Chicago")!
        let source = DemoClubEventsDataSource(now: { reference }, latencySeconds: 0)
        let snapshot = try await source.loadClubEvents()
        XCTAssertEqual(snapshot.clubs.count, 13)

        let schedule = WeekSchedule(events: snapshot.events, now: reference, timeZone: nashville)
        let runsOnly = RunFilter(runsOnly: true)
        for weekday in Weekday.allCases {
            let day = try XCTUnwrap(schedule.day(for: weekday))
            let runs = ClubRun.group(schedule.occurrences(on: day), turnout: snapshot.turnout).filter { runsOnly.includes($0) }
            XCTAssertFalse(runs.isEmpty, "Expected demo runs on \(weekday.name)")
        }

        // Tuesday matches the wireframe: four clubs, and Five Points offers two routes.
        let tuesday = ClubRun.group(schedule.occurrences(on: try XCTUnwrap(schedule.day(for: .tuesday))), turnout: snapshot.turnout)
        XCTAssertEqual(tuesday.map(\.club.name), ["Shelby Bottoms Trail Crew", "Music Row Movers", "Five Points Run Club", "Gulch Striders"])
        let fivePoints = try XCTUnwrap(tuesday.first { $0.club.name == "Five Points Run Club" })
        XCTAssertEqual(fivePoints.options.map { $0.event.route?.optionLabel }, ["5 mi loop", "3 mi loop"])
        XCTAssertEqual(fivePoints.turnout?.average, 75)
        XCTAssertEqual(fivePoints.timeParts.time, "6:00")
        XCTAssertEqual(fivePoints.timeParts.period, "PM")
        XCTAssertEqual(fivePoints.place.area, "Five Points")

        // Saturday's bike ride is hidden by "Runs only".
        let saturday = ClubRun.group(schedule.occurrences(on: try XCTUnwrap(schedule.day(for: .saturday))))
        XCTAssertEqual(saturday.count, 3)
        XCTAssertEqual(saturday.filter { runsOnly.includes($0) }.count, 2)

        let routeID = try XCTUnwrap(fivePoints.primary.event.route?.id)
        let route = try await source.routeDetails(id: routeID)
        XCTAssertEqual(route.distance ?? 0, 5 * 1_609.344, accuracy: 1)
        XCTAssertEqual(route.coordinates.pathLength, 5 * 1_609.344, accuracy: 80, "The drawn loop matches its stated distance")
        XCTAssertTrue(route.isLoop)

        let attendees = try await source.attendees(eventID: fivePoints.primary.event.id)
        XCTAssertEqual(attendees.count, 84)
        let admins = try await source.clubAdmins(clubID: fivePoints.club.id)
        XCTAssertEqual(admins.count, 2)
    }
}
