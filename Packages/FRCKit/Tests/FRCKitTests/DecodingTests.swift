import XCTest
@testable import FRCKit

final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testDecodesRealGroupEventPayload() throws {
        let event = try decode(StravaGroupEvent.self, Fixtures.realGroupEvent)

        // IDs beyond 2^53 must survive exactly.
        XCTAssertEqual(event.id.rawValue, "3468204764614160646")
        XCTAssertEqual(event.route?.id?.rawValue, "3465434395661532938")

        XCTAssertEqual(event.title, "Club Recurring Event with Route")
        XCTAssertEqual(event.eventDescription, "Event description")
        XCTAssertEqual(event.clubID, 1752189)
        XCTAssertEqual(event.organizingAthlete?.displayName, "Valera L.")
        XCTAssertNotNil(event.organizingAthlete?.profileImageURL)
        XCTAssertEqual(event.activityType, "Ride")
        XCTAssertFalse(event.isRun)
        XCTAssertEqual(event.route?.name, "South Road Ride 108 Public")
        XCTAssertTrue(event.isPrivate)
        XCTAssertFalse(event.womenOnly)
        XCTAssertNil(event.skillLevelLabel)
        XCTAssertNil(event.terrainLabel)
        XCTAssertEqual(event.timeZoneIdentifier, "Europe/Warsaw")
        XCTAssertEqual(event.timeZone?.identifier, "Europe/Warsaw")
        XCTAssertEqual(event.address, "Warsaw, MZ, Poland")
        XCTAssertTrue(event.joined)
        XCTAssertEqual(event.startCoordinate, Coordinate(latitude: 52.237695, longitude: 21.005427))
        XCTAssertEqual(event.upcomingOccurrences, [Date(timeIntervalSince1970: 1_774_339_200)]) // 2026-03-24T08:00:00Z
        XCTAssertEqual(event.stravaURL.absoluteString, "https://www.strava.com/clubs/1752189/group_events/3468204764614160646")

        // The embedded route polyline is a 221-point loop around Warsaw.
        let path = try XCTUnwrap(event.route?.coordinates)
        XCTAssertEqual(path.count, 221)
        XCTAssertEqual(path.first?.latitude ?? 0, 52.15353, accuracy: 0.000001)
        XCTAssertEqual(path.first?.longitude ?? 0, 21.09072, accuracy: 0.000001)
        XCTAssertEqual(path.first, path.last)
    }

    func testEventListSkipsMalformedEntriesAndToleratesOddFields() throws {
        let list = try decode(LossyArray<StravaGroupEvent>.self, Fixtures.clubEventsList)
        XCTAssertEqual(list.rawCount, 4)
        XCTAssertEqual(list.elements.map(\.id.rawValue), ["101", "102"])

        let first = list.elements[0]
        XCTAssertEqual(first.upcomingOccurrences.count, 2, "Fractional-second timestamps should parse too")
        XCTAssertEqual(first.startCoordinate, Coordinate(latitude: 40.72, longitude: -73.95))
        XCTAssertTrue(first.isRun)

        let second = list.elements[1]
        XCTAssertEqual(second.title, "Club event", "Blank titles fall back to a placeholder")
        XCTAssertEqual(second.clubID, 55, "Club ID falls back to the embedded club")
        XCTAssertNil(second.activityType, "A wrong-typed field decodes as nil instead of failing")
        XCTAssertTrue(second.isRun, "Events without an activity type aren't hidden by 'Runs only'")
        XCTAssertEqual(second.upcomingOccurrences.count, 1, "Unparseable dates are dropped")
        XCTAssertNil(second.startCoordinate)
        XCTAssertNil(second.address)
        XCTAssertTrue(second.womenOnly)
        XCTAssertEqual(second.terrainLabel, "Killer climbs")
    }

    func testClubAdminsWithoutIDsOrPhotos() throws {
        let admins = try decode(LossyArray<StravaAthlete>.self, Fixtures.clubAdmins).elements
        XCTAssertEqual(admins.count, 3)

        XCTAssertNil(admins[0].id)
        XCTAssertEqual(admins[0].displayName, "Peter S.")
        XCTAssertEqual(admins[0].initials, "PS")

        XCTAssertEqual(admins[1].displayName, "Ana L.")
        XCTAssertNil(admins[1].profileImageURL, "Strava's placeholder avatar path isn't a real URL")

        XCTAssertEqual(admins[2].displayName, "Kofi")
        XCTAssertEqual(admins[2].profileImageURL?.absoluteString, "https://example.com/kofi.jpg")
    }

    func testDecodesAthleteClubs() throws {
        let clubs = try decode(LossyArray<StravaClub>.self, Fixtures.athleteClubs).elements
        let club = try XCTUnwrap(clubs.first)
        XCTAssertEqual(club.id, 1752189)
        XCTAssertEqual(club.name, "Club Events Testing Club")
        XCTAssertEqual(club.sportType, "running")
        XCTAssertEqual(club.memberCount, 1)
        XCTAssertTrue(club.isPrivate)
        XCTAssertEqual(club.stravaURL.absoluteString, "https://www.strava.com/clubs/club-events")
        XCTAssertEqual(club.locationDescription, "Warszawa, Masovian Voivodeship")
    }

    func testDecodesRouteDetailsAndPrefersDetailedPolyline() throws {
        let route = try decode(StravaRoute.self, Fixtures.route)
        XCTAssertEqual(route.id?.rawValue, "3465434395661532938")
        XCTAssertEqual(route.distance, 108123.4)
        XCTAssertEqual(route.elevationGain, 612)
        XCTAssertEqual(route.estimatedMovingTime, 14400)
        XCTAssertEqual(route.coordinates.count, 2, "The detailed polyline wins when present")

        let summaryOnly = StravaRoute(id: "1", summaryPolyline: route.summaryPolyline)
        XCTAssertEqual(summaryOnly.merged(with: route).distance, 108123.4)
        XCTAssertEqual(summaryOnly.coordinates.count, 3)
    }

    func testStravaIDDecodesNumbersAndStrings() throws {
        let ids = try decode([StravaID].self, #"[3468204764614160646, "3465434395661532938", 12]"#)
        XCTAssertEqual(ids.map(\.rawValue), ["3468204764614160646", "3465434395661532938", "12"])
    }

    func testSkillLevelBitmaskAndActivityLabels() {
        func event(skill: Int?, type: String?) -> StravaGroupEvent {
            StravaGroupEvent(id: "1", title: "t", activityType: type, skillLevels: skill, upcomingOccurrences: [])
        }
        XCTAssertEqual(event(skill: 1, type: "Run").skillLevelLabel, "Casual (no drop)")
        XCTAssertEqual(event(skill: 6, type: "Run").skillLevelLabel, "Tempo · Race pace")
        XCTAssertNil(event(skill: 0, type: "Run").skillLevelLabel)
        XCTAssertEqual(event(skill: nil, type: "TrailRun").activityLabel, "Trail Run")
        XCTAssertTrue(event(skill: nil, type: "TrailRun").isRun)
        XCTAssertFalse(event(skill: nil, type: "Ride").isRun)
    }
}
