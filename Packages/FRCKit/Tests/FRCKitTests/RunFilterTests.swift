import XCTest
@testable import FRCKit

final class RunFilterTests: XCTestCase {
    private let nashville = TimeZone(identifier: "America/Chicago")!

    /// A run on Tuesday 2026-09-29 at the given local time, with routes of the given lengths.
    private func run(
        club: StravaClub = StravaClub(id: 1, name: "Five Points Run Club", city: "Nashville"),
        hour: Int,
        minute: Int = 0,
        miles: [Double] = [5],
        type: String = "Run",
        title: String = "Tuesday Night Run",
        address: String? = "Woodland St & 11th St, Five Points, Nashville, TN"
    ) -> ClubRun {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = nashville
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute))!
        let occurrences = miles.enumerated().map { index, distance in
            EventOccurrence(
                event: StravaGroupEvent(
                    id: StravaID("\(club.id)-\(hour)-\(index)"),
                    title: title,
                    activityType: type,
                    route: StravaRoute(id: StravaID("r\(index)"), distance: distance * 1_609.344),
                    upcomingOccurrences: [start],
                    timeZoneIdentifier: nashville.identifier,
                    address: address,
                    startCoordinate: Coordinate(latitude: 36.1769, longitude: -86.7492)
                ),
                club: club,
                start: start
            )
        }
        return ClubRun.group(occurrences)[0]
    }

    func testEventsFromOneClubAtOneTimeAndPlaceBecomeRouteOptions() {
        let club = StravaClub(id: 1, name: "Five Points Run Club")
        let otherClub = StravaClub(id: 2, name: "Gulch Striders")
        let start = Date(timeIntervalSince1970: 1_790_722_800)
        let spot = Coordinate(latitude: 36.1769, longitude: -86.7492)
        func occurrence(_ id: String, _ club: StravaClub, miles: Double) -> EventOccurrence {
            EventOccurrence(
                event: StravaGroupEvent(
                    id: StravaID(id), title: id,
                    route: StravaRoute(distance: miles * 1_609.344),
                    upcomingOccurrences: [start], startCoordinate: spot
                ),
                club: club, start: start
            )
        }
        let runs = ClubRun.group(
            [occurrence("short", club, miles: 3), occurrence("long", club, miles: 5), occurrence("other", otherClub, miles: 4)],
            turnout: [StravaID("short"): TurnoutHistory(weekly: [10, 12])]
        )
        XCTAssertEqual(runs.count, 2)
        let fivePoints = try? XCTUnwrap(runs.first { $0.club.id == 1 })
        XCTAssertEqual(fivePoints?.options.map(\.event.id.rawValue), ["long", "short"], "Longest route first")
        XCTAssertEqual(fivePoints?.distanceLabel, "3.0 / 5.0 mi")
        XCTAssertEqual(fivePoints?.turnout?.average, 11, "Turnout comes from whichever option has it")
    }

    func testTimeSlotsAndStartWindow() {
        let early = run(hour: 6)
        let lunch = run(hour: 12, minute: 10)
        let evening = run(hour: 18, minute: 30)

        XCTAssertEqual(early.minuteOfDay, 360)
        XCTAssertTrue(RunFilter(timeSlot: .early).includes(early))
        XCTAssertFalse(RunFilter(timeSlot: .early).includes(lunch))
        XCTAssertTrue(RunFilter(timeSlot: .midday).includes(lunch))
        XCTAssertTrue(RunFilter(timeSlot: .evening).includes(evening))
        XCTAssertTrue(RunFilter(timeSlot: .any).includes(evening))

        let morningWindow = RunFilter(earliestMinute: 5 * 60, latestMinute: 13 * 60)
        XCTAssertTrue(morningWindow.includes(early))
        XCTAssertTrue(morningWindow.includes(lunch))
        XCTAssertFalse(morningWindow.includes(evening))
        XCTAssertTrue(RunFilter(earliestMinute: 13 * 60, latestMinute: 5 * 60).includes(lunch), "A reversed window still works")
    }

    func testDistanceRunsOnlyClubsAndSearch() {
        let fivePoints = run(hour: 18, miles: [5, 3])
        let longRun = run(hour: 7, miles: [10])
        let ride = run(club: StravaClub(id: 3, name: "East Bank Riders"), hour: 7, miles: [20], type: "Ride", title: "Coffee Ride")

        XCTAssertTrue(RunFilter(distance: .under3).includes(run(hour: 18, miles: [2.5])))
        XCTAssertTrue(RunFilter(distance: .threeToSix).includes(fivePoints))
        XCTAssertFalse(RunFilter(distance: .sixPlus).includes(fivePoints))
        XCTAssertTrue(RunFilter(distance: .sixPlus).includes(longRun))
        XCTAssertFalse(DistanceBucket.under3.contains(miles: nil), "Unknown distances only match Any")

        XCTAssertFalse(RunFilter(runsOnly: true).includes(ride))
        XCTAssertTrue(RunFilter(runsOnly: false).includes(ride))
        XCTAssertFalse(RunFilter(hiddenClubIDs: [1]).includes(fivePoints))

        XCTAssertTrue(RunFilter().includes(fivePoints, search: "five points"))
        XCTAssertTrue(RunFilter().includes(fivePoints, search: "NIGHT RUN"))
        XCTAssertTrue(RunFilter().includes(fivePoints, search: "nashville"))
        XCTAssertFalse(RunFilter().includes(fivePoints, search: "gulch"))
    }

    func testDaysLabel() {
        XCTAssertEqual(RunFilter().daysLabel, "Every day")
        XCTAssertEqual(RunFilter(days: [.tuesday]).daysLabel, "Tuesday")
        XCTAssertEqual(RunFilter(days: [.sunday, .monday, .thursday]).daysLabel, "Mon, Thu, Sun")
        XCTAssertEqual(Weekday(LocalDay(year: 2026, month: 9, day: 29)), .tuesday)
        XCTAssertEqual(Weekday.allCases.first, .monday)
    }

    func testTurnoutMetricsMatchTheWireframe() {
        // Five Points Run Club in the design handoff.
        let turnout = TurnoutHistory(weekly: [62, 66, 70, 71, 78, 80, 86, 84])
        XCTAssertEqual(turnout.average, 75)
        XCTAssertEqual(turnout.peak, 86)
        XCTAssertEqual(turnout.latest, 84)
        XCTAssertEqual(turnout.growthPercent, 33)
        XCTAssertNil(TurnoutHistory(weekly: [5, 6]).growthPercent)
        XCTAssertNil(TurnoutHistory(weekly: []).average)
    }

    func testPlaceDescriptionFromStravaAddresses() {
        let full = PlaceDescription(address: "Woodland St & 11th St, Five Points, Nashville, TN")
        XCTAssertEqual(full.area, "Five Points")
        XCTAssertEqual(full.meetingPoint, "Woodland St & 11th St, Five Points")

        let short = PlaceDescription(address: "Warsaw, MZ, Poland")
        XCTAssertEqual(short.area, "Warsaw")

        let missing = PlaceDescription(address: nil, fallbackArea: "Nashville")
        XCTAssertEqual(missing.area, "Nashville")
        XCTAssertNil(missing.meetingPoint)
    }

    func testRouteLabelsAndMeasuredDistance() {
        XCTAssertEqual(StravaRoute(distance: 5 * 1_609.344).optionLabel, "5 mi")
        XCTAssertEqual(StravaRoute(distance: 3.1 * 1_609.344).optionLabel, "3.1 mi")
        XCTAssertEqual(StravaRoute(name: "Mystery route").optionLabel, "Mystery route")

        // No distance from Strava: measure along the line instead.
        let line = [Coordinate(latitude: 36.0, longitude: -86.0), Coordinate(latitude: 36.01, longitude: -86.0)]
        let measured = StravaRoute(summaryPolyline: Polyline.encode(line))
        XCTAssertEqual(measured.estimatedDistance ?? 0, 1_112, accuracy: 5)
        XCTAssertFalse(measured.isLoop)

        let loop = DemoCatalog.loop(from: line[0], meters: 5_000, headingDegrees: 45)
        XCTAssertEqual(loop.pathLength, 5_000, accuracy: 1)
        XCTAssertTrue(StravaRoute(summaryPolyline: Polyline.encode(loop)).isLoop)
    }
}
