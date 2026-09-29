import Foundation

/// Fictional run clubs around New York City with weekly runs generated
/// relative to "now", so every day of the week has something to show.
///
/// Used before Strava is connected, and handy for QA: it exercises stacked
/// pins (two runs from one spot), a women-only run, a run you've joined,
/// runs with and without routes, and a bike ride hidden by "Runs only".
public struct DemoClubEventsDataSource: ClubEventsDataSource {
    public static let timeZoneIdentifier = "America/New_York"

    private let now: @Sendable () -> Date
    private let latencySeconds: Double

    public init(now: @escaping @Sendable () -> Date = { Date() }, latencySeconds: Double = 0.4) {
        self.now = now
        self.latencySeconds = latencySeconds
    }

    public func loadClubEvents() async throws -> ClubEventsSnapshot {
        try await simulateLatency()
        let reference = now()
        let events = DemoCatalog.events.compactMap { definition -> ClubEvent? in
            guard let club = DemoCatalog.club(id: definition.clubID) else { return nil }
            return ClubEvent(event: definition.makeEvent(now: reference), club: club)
        }
        return ClubEventsSnapshot(clubs: DemoCatalog.clubs, events: events, loadedAt: reference)
    }

    public func clubAdmins(clubID: Int) async throws -> [StravaAthlete] {
        try await simulateLatency()
        return DemoCatalog.admins[clubID] ?? []
    }

    public func attendees(eventID: StravaID) async throws -> [StravaAthlete] {
        try await simulateLatency()
        guard let index = DemoCatalog.events.firstIndex(where: { $0.id == eventID.rawValue }) else {
            throw StravaAPIError.notFound
        }
        return DemoCatalog.athletes(count: DemoCatalog.events[index].attendeeCount, seed: index * 7)
    }

    public func routeDetails(id: StravaID) async throws -> StravaRoute {
        try await simulateLatency()
        guard let definition = DemoCatalog.events.first(where: { $0.routeID == id.rawValue }) else {
            throw StravaAPIError.notFound
        }
        return definition.makeRoute(detailed: true) ?? StravaRoute(id: id)
    }

    private func simulateLatency() async throws {
        guard latencySeconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(latencySeconds * 1_000_000_000))
    }
}

// MARK: - Catalog

struct DemoEventDefinition: Sendable {
    let id: String
    let clubID: Int
    let title: String
    let description: String
    let host: StravaAthlete
    var activityType = "Run"
    /// 1 = Sunday … 7 = Saturday.
    let weekdays: [Int]
    let hour: Int
    let minute: Int
    let start: Coordinate
    let address: String
    var routeName: String?
    /// One-way path; `outAndBack` retraces it to the start.
    var routePath: [Coordinate] = []
    var outAndBack = false
    var elevationGain: Double = 0
    var skillLevels: Int?
    var terrain: Int?
    var womenOnly = false
    var joined = false
    let attendeeCount: Int

    var routeID: String? {
        routePath.isEmpty ? nil : "demo-route-\(id)"
    }

    func makeEvent(now: Date) -> StravaGroupEvent {
        StravaGroupEvent(
            id: StravaID(id),
            title: title,
            eventDescription: description,
            clubID: clubID,
            organizingAthlete: host,
            activityType: activityType,
            route: makeRoute(detailed: false),
            womenOnly: womenOnly,
            skillLevels: skillLevels,
            terrain: terrain,
            upcomingOccurrences: occurrences(after: now),
            timeZoneIdentifier: DemoClubEventsDataSource.timeZoneIdentifier,
            address: address,
            joined: joined,
            startCoordinate: start,
            frequency: "weekly",
            daysOfWeek: weekdays.map(Self.weekdayName)
        )
    }

    /// The embedded summary has only name + polyline, like Strava's; the
    /// detailed version adds distance, elevation and time.
    func makeRoute(detailed: Bool) -> StravaRoute? {
        guard let routeID else { return nil }
        let path = outAndBack ? routePath + routePath.reversed().dropFirst() : routePath
        let polyline = Polyline.encode(path)
        guard detailed else {
            return StravaRoute(id: StravaID(routeID), name: routeName, summaryPolyline: polyline)
        }
        let distance = DemoCatalog.distance(along: path)
        let metersPerSecond = activityType == "Ride" ? 7.0 : 2.8
        return StravaRoute(
            id: StravaID(routeID),
            name: routeName,
            distance: distance,
            elevationGain: elevationGain,
            estimatedMovingTime: distance / metersPerSecond,
            summaryPolyline: polyline,
            detailedPolyline: polyline
        )
    }

    /// This week's and next week's occurrence for each weekday, like Strava's
    /// `upcoming_occurrences` (runs that started under an hour ago still count).
    func occurrences(after now: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: DemoClubEventsDataSource.timeZoneIdentifier) ?? .current
        let searchStart = now.addingTimeInterval(-60 * 60)
        return weekdays.flatMap { weekday -> [Date] in
            let components = DateComponents(hour: hour, minute: minute, weekday: weekday)
            guard let next = calendar.nextDate(after: searchStart, matching: components, matchingPolicy: .nextTime) else {
                return []
            }
            return [next, calendar.date(byAdding: .day, value: 7, to: next)].compactMap { $0 }
        }
        .sorted()
    }

    static func weekdayName(_ weekday: Int) -> String {
        ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][(weekday - 1 + 7) % 7]
    }
}

enum DemoCatalog {
    static func club(id: Int) -> StravaClub? {
        clubs.first { $0.id == id }
    }

    static let clubs: [StravaClub] = [
        StravaClub(id: 9_000_001, name: "Hudson River Striders", sportType: "running", city: "New York", state: "NY", memberCount: 1_240),
        StravaClub(id: 9_000_002, name: "Prospect Park Pacers", sportType: "running", city: "Brooklyn", state: "NY", memberCount: 860),
        StravaClub(id: 9_000_003, name: "Bridge Runners Collective", sportType: "running", city: "New York", state: "NY", memberCount: 2_105),
        StravaClub(id: 9_000_004, name: "Central Park Dawn Patrol", sportType: "running", city: "New York", state: "NY", memberCount: 530),
        StravaClub(id: 9_000_005, name: "Williamsburg Track Social", sportType: "running", city: "Brooklyn", state: "NY", memberCount: 415),
        StravaClub(id: 9_000_006, name: "Astoria Afterwork Run Club", sportType: "running", city: "Queens", state: "NY", memberCount: 380),
        StravaClub(id: 9_000_007, name: "Harlem Hill Seekers", sportType: "running", city: "New York", state: "NY", memberCount: 290),
        StravaClub(id: 9_000_008, name: "Five Boro Spin Crew", sportType: "cycling", city: "New York", state: "NY", memberCount: 640),
    ]

    static let admins: [Int: [StravaAthlete]] = [
        9_000_001: [person(0), person(9)],
        9_000_002: [person(1), person(10)],
        9_000_003: [person(2), person(11), person(12)],
        9_000_004: [person(3)],
        9_000_005: [person(4), person(13)],
        9_000_006: [person(5), person(14)],
        9_000_007: [person(6)],
        9_000_008: [person(7), person(15)],
    ]

    // MARK: Places & paths

    static let chelseaPiers = Coordinate(latitude: 40.7466, longitude: -74.0080)
    static let grandArmyPlaza = Coordinate(latitude: 40.6740, longitude: -73.9701)
    static let cityHallPark = Coordinate(latitude: 40.7127, longitude: -74.0048)
    static let engineersGate = Coordinate(latitude: 40.7846, longitude: -73.9590)
    static let mccarrenTrack = Coordinate(latitude: 40.7206, longitude: -73.9510)
    static let astoriaPark = Coordinate(latitude: 40.7797, longitude: -73.9227)
    static let harlemMeer = Coordinate(latitude: 40.7967, longitude: -73.9519)

    static let hudsonShort: [Coordinate] = [chelseaPiers] + points((40.7530, -74.0062), (40.7590, -74.0030))
    static let hudson5K: [Coordinate] = [chelseaPiers] + points((40.7530, -74.0062), (40.7590, -74.0030), (40.7640, -73.9990), (40.7670, -73.9965))
    static let hudsonLong: [Coordinate] = [chelseaPiers] + points(
        (40.7530, -74.0062), (40.7590, -74.0030), (40.7640, -73.9990), (40.7720, -73.9935),
        (40.7765, -73.9905), (40.7830, -73.9850), (40.7900, -73.9800), (40.7965, -73.9765)
    )
    static let hudsonToGWB: [Coordinate] = hudsonLong + points((40.8100, -73.9650), (40.8270, -73.9530), (40.8400, -73.9480), (40.8505, -73.9465))
    static let prospectLoop: [Coordinate] = [grandArmyPlaza] + points(
        (40.6712, -73.9722), (40.6665, -73.9750), (40.6618, -73.9782), (40.6570, -73.9745),
        (40.6546, -73.9695), (40.6558, -73.9630), (40.6600, -73.9622), (40.6650, -73.9640), (40.6700, -73.9668)
    ) + [grandArmyPlaza]
    static let brooklynBridge: [Coordinate] = [cityHallPark] + points(
        (40.7110, -74.0030), (40.7080, -73.9990), (40.7061, -73.9969), (40.7040, -73.9930), (40.7025, -73.9900), (40.7033, -73.9881)
    )
    static let reservoirLoop: [Coordinate] = [engineersGate] + points(
        (40.7880, -73.9583), (40.7893, -73.9610), (40.7885, -73.9655), (40.7860, -73.9680),
        (40.7825, -73.9683), (40.7812, -73.9660), (40.7815, -73.9620), (40.7830, -73.9595)
    ) + [engineersGate]
    static let mccarrenOval: [Coordinate] = [mccarrenTrack] + points((40.7214, -73.9505), (40.7203, -73.9500), (40.7200, -73.9513)) + [mccarrenTrack]
    static let dominoParkLoop: [Coordinate] = [mccarrenTrack] + points(
        (40.7180, -73.9560), (40.7150, -73.9610), (40.7140, -73.9665), (40.7165, -73.9640), (40.7195, -73.9570)
    ) + [mccarrenTrack]
    static let astoriaLoop: [Coordinate] = [astoriaPark] + points((40.7815, -73.9228), (40.7800, -73.9200), (40.7775, -73.9215)) + [astoriaPark]
    static let harlemHillLoop: [Coordinate] = [harlemMeer] + points(
        (40.7978, -73.9560), (40.7960, -73.9585), (40.7930, -73.9605), (40.7905, -73.9590), (40.7910, -73.9545), (40.7940, -73.9525)
    ) + [harlemMeer]

    // MARK: Events

    static let events: [DemoEventDefinition] = [
        DemoEventDefinition(
            id: "demo-101", clubID: 9_000_001, title: "Tuesday Easy Miles",
            description: "Conversational pace along the Hudson River Greenway. Everyone finishes together. Bag drop at the pier.",
            host: person(0), weekdays: [3], hour: 6, minute: 0, start: chelseaPiers,
            address: "Pier 62, Chelsea Piers, New York, NY", routeName: "Greenway Easy 3K",
            routePath: hudsonShort, outAndBack: true, elevationGain: 8, skillLevels: 1, terrain: 0, attendeeCount: 14
        ),
        DemoEventDefinition(
            id: "demo-102", clubID: 9_000_001, title: "Sunset 5K on the Greenway",
            description: "Out-and-back 5K timed to the sunset. Pace groups from 7:00 to 10:00 min/mile. Drinks after at the pier.",
            host: person(9), weekdays: [3, 5], hour: 18, minute: 30, start: chelseaPiers,
            address: "Pier 62, Chelsea Piers, New York, NY", routeName: "Greenway Sunset 5K",
            routePath: hudson5K, outAndBack: true, elevationGain: 12, skillLevels: 2, terrain: 0, joined: true, attendeeCount: 38
        ),
        DemoEventDefinition(
            id: "demo-103", clubID: 9_000_001, title: "Saturday Long Run",
            description: "Long run up the West Side to Riverside Park. Choose 8, 10 or 13 miles. Water stop at 72nd St.",
            host: person(0), weekdays: [7], hour: 8, minute: 0, start: chelseaPiers,
            address: "Pier 62, Chelsea Piers, New York, NY", routeName: "West Side Long Run",
            routePath: hudsonLong, outAndBack: true, elevationGain: 35, skillLevels: 3, terrain: 0, attendeeCount: 52
        ),
        DemoEventDefinition(
            id: "demo-201", clubID: 9_000_002, title: "Hill Repeats at Lookout Hill",
            description: "Warm-up loop, then 6-8 repeats on Lookout Hill. Bring a headlamp in winter.",
            host: person(1), weekdays: [4], hour: 6, minute: 15, start: grandArmyPlaza,
            address: "Grand Army Plaza, Brooklyn, NY", routeName: "Prospect Park Loop",
            routePath: prospectLoop, elevationGain: 45, skillLevels: 2, terrain: 1, attendeeCount: 21
        ),
        DemoEventDefinition(
            id: "demo-202", clubID: 9_000_002, title: "Sunday Loop + Coffee",
            description: "One or two laps of the park, then coffee on Vanderbilt. No-drop, all paces welcome.",
            host: person(10), weekdays: [1], hour: 9, minute: 0, start: grandArmyPlaza,
            address: "Grand Army Plaza, Brooklyn, NY", routeName: "Prospect Park Loop",
            routePath: prospectLoop, elevationGain: 45, skillLevels: 1, terrain: 1, attendeeCount: 64
        ),
        DemoEventDefinition(
            id: "demo-301", clubID: 9_000_003, title: "Brooklyn Bridge Night Run",
            description: "Across the bridge to DUMBO and back. Reflective gear recommended.",
            host: person(2), weekdays: [5], hour: 19, minute: 0, start: cityHallPark,
            address: "City Hall Park, New York, NY", routeName: "Bridge Out & Back",
            routePath: brooklynBridge, outAndBack: true, elevationGain: 40, skillLevels: 1, terrain: 1, attendeeCount: 87
        ),
        DemoEventDefinition(
            id: "demo-302", clubID: 9_000_003, title: "Women's Run Crew",
            description: "A supportive women-only run over the bridge. Walk breaks welcome.",
            host: person(11), weekdays: [2], hour: 18, minute: 30, start: cityHallPark,
            address: "City Hall Park, New York, NY", routeName: "Bridge Out & Back",
            routePath: brooklynBridge, outAndBack: true, elevationGain: 40, skillLevels: 1, terrain: 1, womenOnly: true, attendeeCount: 29
        ),
        DemoEventDefinition(
            id: "demo-303", clubID: 9_000_003, title: "Sunday Two Bridges Long Run",
            description: "Brooklyn Bridge out, Manhattan Bridge back, then brunch. 8-10 miles.",
            host: person(12), weekdays: [1], hour: 8, minute: 30, start: cityHallPark,
            address: "City Hall Park, New York, NY", routeName: "Bridge Out & Back",
            routePath: brooklynBridge, outAndBack: true, elevationGain: 55, skillLevels: 3, terrain: 1, attendeeCount: 41
        ),
        DemoEventDefinition(
            id: "demo-401", clubID: 9_000_004, title: "Reservoir Sunrise Loop",
            description: "1.6-mile loops of the Reservoir. Run one or four; we regroup at Engineers' Gate each lap.",
            host: person(3), weekdays: [2, 4, 6], hour: 6, minute: 0, start: engineersGate,
            address: "Engineers' Gate, E 90th St & 5th Ave, New York, NY", routeName: "Reservoir Loop",
            routePath: reservoirLoop, elevationGain: 8, skillLevels: 1, terrain: 0, attendeeCount: 18
        ),
        DemoEventDefinition(
            id: "demo-501", clubID: 9_000_005, title: "Track Tuesday",
            description: "Structured intervals on the McCarren track. Workout posted in the club feed Monday night.",
            host: person(4), weekdays: [3], hour: 19, minute: 0, start: mccarrenTrack,
            address: "McCarren Park Track, Brooklyn, NY", routeName: "McCarren Track",
            routePath: mccarrenOval, elevationGain: 0, skillLevels: 4, terrain: 0, attendeeCount: 33
        ),
        DemoEventDefinition(
            id: "demo-502", clubID: 9_000_005, title: "Easy Social Run to Domino Park",
            description: "Easy 5K down to the waterfront and back. Hang out after.",
            host: person(13), weekdays: [5], hour: 19, minute: 0, start: mccarrenTrack,
            address: "McCarren Park Track, Brooklyn, NY", routeName: "Domino Park Loop",
            routePath: dominoParkLoop, elevationGain: 15, skillLevels: 1, terrain: 0, attendeeCount: 45
        ),
        DemoEventDefinition(
            id: "demo-601", clubID: 9_000_006, title: "Astoria Park Loops",
            description: "Loops of Astoria Park under the Hell Gate Bridge. Pick 3 or 5 miles.",
            host: person(5), weekdays: [4], hour: 18, minute: 45, start: astoriaPark,
            address: "Astoria Park, Queens, NY", routeName: "Astoria Park Loop",
            routePath: astoriaLoop, elevationGain: 20, skillLevels: 3, terrain: 1, attendeeCount: 26
        ),
        DemoEventDefinition(
            id: "demo-602", clubID: 9_000_006, title: "Friday Shakeout",
            description: "Short and slow to kick off the weekend. Route decided on the day.",
            host: person(14), weekdays: [6], hour: 18, minute: 0, start: astoriaPark,
            address: "Astoria Park, Queens, NY", skillLevels: 1, attendeeCount: 12
        ),
        DemoEventDefinition(
            id: "demo-701", clubID: 9_000_007, title: "Harlem Hill Repeats",
            description: "The steepest hill in Central Park, five times. Coffee is on the club afterwards.",
            host: person(6), weekdays: [7], hour: 7, minute: 0, start: harlemMeer,
            address: "Dana Discovery Center, Central Park, New York, NY", routeName: "Harlem Hill Loop",
            routePath: harlemHillLoop, elevationGain: 60, skillLevels: 6, terrain: 2, attendeeCount: 17
        ),
        DemoEventDefinition(
            id: "demo-801", clubID: 9_000_008, title: "Saturday Hudson Ride",
            description: "Social ride up the Greenway to the GW Bridge. 18-20 mph.",
            host: person(7), activityType: "Ride", weekdays: [7], hour: 7, minute: 30, start: chelseaPiers,
            address: "Pier 62, Chelsea Piers, New York, NY", routeName: "Greenway to GWB",
            routePath: hudsonToGWB, outAndBack: true, elevationGain: 120, skillLevels: 2, terrain: 1, attendeeCount: 22
        ),
    ]

    // MARK: People (fictional)

    private static let firstNames = [
        "Maya", "Jordan", "Priya", "Marcus", "Elena", "Sam", "Diego", "Aisha", "Tom", "Keiko",
        "Luis", "Nora", "Andre", "Grace", "Omar", "Hannah", "Leo", "Zoe", "Ravi", "Chloe",
        "Mateo", "Imani", "Ben", "Sofia", "Kai", "Rosa", "Ethan", "Lina", "Noah", "Ava",
    ]
    private static let lastNames = [
        "Rivera", "Chen", "Patel", "Johnson", "Novak", "Kim", "Alvarez", "Okafor", "Brennan", "Tanaka",
        "Morales", "Fischer", "Williams", "Nguyen", "Haddad", "Schultz", "Rossi", "Park", "Iyer", "Dubois",
        "Garcia", "Mensah", "Cohen", "Silva", "Moreau", "Lopez", "Walsh", "Sato", "Brooks", "Ahmed",
    ]

    static func person(_ index: Int) -> StravaAthlete {
        let first = firstNames[index % firstNames.count]
        let last = lastNames[(index * 7 + 3) % lastNames.count]
        return StravaAthlete(id: 70_000_000 + index, firstName: first, lastName: last, city: "New York", state: "NY")
    }

    static func athletes(count: Int, seed: Int) -> [StravaAthlete] {
        (0..<count).map { person(seed + $0 * 3) }
    }

    // MARK: Geometry helpers

    private static func points(_ pairs: (Double, Double)...) -> [Coordinate] {
        pairs.map { Coordinate(latitude: $0.0, longitude: $0.1) }
    }

    /// Great-circle distance along a path, in meters.
    static func distance(along path: [Coordinate]) -> Double {
        zip(path, path.dropFirst()).reduce(0.0) { total, segment in
            total + haversine(segment.0, segment.1)
        }
    }

    private static func haversine(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLng = (b.longitude - a.longitude) * .pi / 180
        let h = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }
}
