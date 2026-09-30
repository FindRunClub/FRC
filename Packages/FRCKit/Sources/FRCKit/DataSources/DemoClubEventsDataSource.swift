import Foundation

/// The fictional Nashville run clubs from the design handoff
/// (`data/sample-clubs.json`), turned into Strava-shaped events with routes,
/// hosts, admins, attendees and 8-week turnout. Dates are generated relative
/// to "now" so every day of the week has runs.
///
/// Used before Strava is connected, and for QA: it covers runs with two route
/// options (Five Points, Centennial, Sunday Long Run), a run you've joined
/// (12South), a trail run, a bike ride hidden by "Runs only", and a mix of
/// clubs you belong to (4) and other clubs in the area (9).
public struct DemoClubEventsDataSource: ClubEventsDataSource {
    public static let timeZoneIdentifier = "America/Chicago"

    private let now: @Sendable () -> Date
    private let latencySeconds: Double

    public init(now: @escaping @Sendable () -> Date = { Date() }, latencySeconds: Double = 0.4) {
        self.now = now
        self.latencySeconds = latencySeconds
    }

    public func loadClubEvents() async throws -> ClubEventsSnapshot {
        try await simulateLatency()
        let reference = now()
        var events: [ClubEvent] = []
        var turnout: [StravaID: TurnoutHistory] = [:]
        for run in DemoCatalog.runs {
            let runEvents = run.makeEvents(now: reference)
            events += runEvents.map { ClubEvent(event: $0, club: run.club) }
            if let primary = runEvents.first {
                turnout[primary.id] = TurnoutHistory(weekly: run.turnout)
            }
        }
        return ClubEventsSnapshot(
            clubs: DemoCatalog.runs.map(\.club).sorted { $0.name < $1.name },
            events: events,
            turnout: turnout,
            loadedAt: reference
        )
    }

    public func clubAdmins(clubID: Int) async throws -> [StravaAthlete] {
        try await simulateLatency()
        guard let index = DemoCatalog.runs.firstIndex(where: { $0.club.id == clubID }) else { return [] }
        return [DemoCatalog.person(index * 3 + 1), DemoCatalog.person(index * 3 + 2)]
    }

    public func attendees(eventID: StravaID) async throws -> [StravaAthlete] {
        try await simulateLatency()
        for (index, run) in DemoCatalog.runs.enumerated() {
            if let option = run.optionIndex(ofEventID: eventID.rawValue) {
                return DemoCatalog.athletes(count: run.goingCount(option: option), seed: index * 5)
            }
        }
        throw StravaAPIError.notFound
    }

    public func routeDetails(id: StravaID) async throws -> StravaRoute {
        try await simulateLatency()
        for run in DemoCatalog.runs {
            for option in run.routes.indices where run.routeID(option: option) == id.rawValue {
                return run.makeRoute(option: option, detailed: true)
            }
        }
        throw StravaAPIError.notFound
    }

    private func simulateLatency() async throws {
        guard latencySeconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(latencySeconds * 1_000_000_000))
    }
}

// MARK: - Catalog

struct DemoRoute: Sendable {
    let miles: Double
    let elevationFeet: Double
    /// Compass direction the loop heads out in, so routes don't all overlap.
    let heading: Double
}

struct DemoRunDefinition: Sendable {
    let id: String
    let club: StravaClub
    let title: String
    let description: String
    let host: StravaAthlete
    var activityType = "Run"
    /// 1 = Sunday … 7 = Saturday.
    let weekday: Int
    let hour: Int
    let minute: Int
    let start: Coordinate
    let address: String
    /// One event per route option, longest first.
    let routes: [DemoRoute]
    var skillLevels: Int?
    var terrain: Int?
    var joined = false
    /// Oldest week first; the last value is this week's RSVP count.
    let turnout: [Int]

    func eventID(option: Int) -> String {
        option == 0 ? "demo-\(id)" : "demo-\(id)-\(option)"
    }

    func routeID(option: Int) -> String {
        "demo-route-\(id)-\(option)"
    }

    func optionIndex(ofEventID eventID: String) -> Int? {
        (0..<max(routes.count, 1)).first { self.eventID(option: $0) == eventID }
    }

    func goingCount(option: Int) -> Int {
        let latest = turnout.last ?? 0
        return option == 0 ? latest : max(4, latest / 3)
    }

    func makeEvents(now: Date) -> [StravaGroupEvent] {
        let dates = occurrences(after: now)
        return (0..<max(routes.count, 1)).map { option in
            let optionTitle = option == 0 || routes.isEmpty
                ? title
                : "\(title) (\(makeRoute(option: option, detailed: false).optionLabel))"
            return StravaGroupEvent(
                id: StravaID(eventID(option: option)),
                title: optionTitle,
                eventDescription: description,
                clubID: club.id,
                organizingAthlete: host,
                activityType: activityType,
                route: routes.isEmpty ? nil : makeRoute(option: option, detailed: false),
                skillLevels: skillLevels,
                terrain: terrain,
                upcomingOccurrences: dates,
                timeZoneIdentifier: DemoClubEventsDataSource.timeZoneIdentifier,
                address: address,
                joined: joined && option == 0,
                startCoordinate: start,
                frequency: "weekly",
                daysOfWeek: [DemoRunDefinition.weekdayName(weekday)]
            )
        }
    }

    /// The embedded summary has only name + line, like Strava's; the detailed
    /// version adds distance and elevation.
    func makeRoute(option: Int, detailed: Bool) -> StravaRoute {
        let route = routes[option]
        let path = DemoCatalog.loop(from: start, meters: route.miles * 1_609.344, headingDegrees: route.heading)
        let polyline = Polyline.encode(path)
        let name = "\(club.name) \(String(format: "%g", route.miles)) mi"
        guard detailed else {
            return StravaRoute(id: StravaID(routeID(option: option)), name: name, summaryPolyline: polyline)
        }
        let meters = route.miles * 1_609.344
        return StravaRoute(
            id: StravaID(routeID(option: option)),
            name: name,
            distance: meters,
            elevationGain: route.elevationFeet / 3.28084,
            estimatedMovingTime: meters / (activityType == "Ride" ? 7.0 : 2.8),
            summaryPolyline: polyline,
            detailedPolyline: polyline
        )
    }

    /// This week's and next week's date, like Strava's `upcoming_occurrences`
    /// (a run that started under an hour ago still counts).
    func occurrences(after now: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: DemoClubEventsDataSource.timeZoneIdentifier) ?? .current
        let components = DateComponents(hour: hour, minute: minute, weekday: weekday)
        guard let next = calendar.nextDate(after: now.addingTimeInterval(-60 * 60), matching: components, matchingPolicy: .nextTime) else {
            return []
        }
        return [next, calendar.date(byAdding: .day, value: 7, to: next)].compactMap { $0 }
    }

    static func weekdayName(_ weekday: Int) -> String {
        ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][(weekday - 1 + 7) % 7]
    }
}

enum DemoCatalog {
    static func club(_ id: Int, _ name: String, members: Int, sport: String = "running", joined: Bool = false) -> StravaClub {
        StravaClub(id: id, name: name, sportType: sport, city: "Nashville", state: "TN", memberCount: members, isMember: joined)
    }

    static let runs: [DemoRunDefinition] = [
        DemoRunDefinition(
            id: "fp", club: club(9_100_001, "Five Points Run Club", members: 1_180, joined: true),
            title: "Tuesday Night Run",
            description: "Two loops through East Nashville, then tacos. Pick 5 miles or 3; everyone regroups at the corner.",
            host: person(0), weekday: 3, hour: 18, minute: 0,
            start: Coordinate(latitude: 36.1769, longitude: -86.7492),
            address: "Woodland St & 11th St, Five Points, Nashville, TN",
            routes: [DemoRoute(miles: 5.0, elevationFeet: 142, heading: 60), DemoRoute(miles: 3.0, elevationFeet: 64, heading: 60)],
            skillLevels: 3, terrain: 1,
            turnout: [62, 66, 70, 71, 78, 80, 86, 84]
        ),
        DemoRunDefinition(
            id: "gs", club: club(9_100_002, "Gulch Striders", members: 940),
            title: "Gulch Tempo Tuesday",
            description: "Steady tempo miles with a pace group every 30 seconds per mile.",
            host: person(3), weekday: 3, hour: 18, minute: 30,
            start: Coordinate(latitude: 36.1519, longitude: -86.7843),
            address: "11th Ave S & Laurel St, The Gulch, Nashville, TN",
            routes: [DemoRoute(miles: 4.0, elevationFeet: 88, heading: 200)],
            skillLevels: 2, terrain: 0,
            turnout: [58, 60, 57, 63, 61, 64, 62, 66]
        ),
        DemoRunDefinition(
            id: "mr", club: club(9_100_003, "Music Row Movers", members: 520),
            title: "Music Row After-Work 5K",
            description: "An easy, no-drop 5K. Walk breaks welcome.",
            host: person(6), weekday: 3, hour: 17, minute: 30,
            start: Coordinate(latitude: 36.1500, longitude: -86.7928),
            address: "Music Square roundabout, Music Row, Nashville, TN",
            routes: [DemoRoute(miles: 3.0, elevationFeet: 75, heading: 250)],
            skillLevels: 1, terrain: 1,
            turnout: [30, 34, 33, 37, 39, 41, 40, 44]
        ),
        DemoRunDefinition(
            id: "sb", club: club(9_100_004, "Shelby Bottoms Trail Crew", members: 310),
            title: "Sunrise Greenway Miles",
            description: "Flat greenway and gravel miles along the river. Headlamps until sunrise.",
            host: person(9), activityType: "TrailRun", weekday: 3, hour: 6, minute: 0,
            start: Coordinate(latitude: 36.1735, longitude: -86.7257),
            address: "Boathouse lot, Shelby Park, Nashville, TN",
            routes: [DemoRoute(miles: 6.0, elevationFeet: 40, heading: 30)],
            skillLevels: 1, terrain: 0,
            turnout: [22, 20, 24, 23, 25, 22, 24, 26]
        ),
        DemoRunDefinition(
            id: "gm", club: club(9_100_005, "Germantown Milers", members: 610, joined: true),
            title: "Wednesday Milers",
            description: "Mile repeats on the Bicentennial Mall loop, then an easy jog back.",
            host: person(12), weekday: 4, hour: 18, minute: 0,
            start: Coordinate(latitude: 36.1785, longitude: -86.7875),
            address: "5th Ave N & Monroe St, Germantown, Nashville, TN",
            routes: [DemoRoute(miles: 3.5, elevationFeet: 55, heading: 320)],
            skillLevels: 2, terrain: 0,
            turnout: [40, 42, 45, 44, 48, 50, 49, 52]
        ),
        DemoRunDefinition(
            id: "ww", club: club(9_100_006, "Wedgewood Lunch Loop", members: 180),
            title: "Lunch Loop",
            description: "Out and back by 1 PM. Showers at the gym next door for members.",
            host: person(15), weekday: 4, hour: 12, minute: 10,
            start: Coordinate(latitude: 36.1340, longitude: -86.7660),
            address: "Martin St & Houston St, Wedgewood-Houston, Nashville, TN",
            routes: [DemoRoute(miles: 3.0, elevationFeet: 48, heading: 150)],
            skillLevels: 1, terrain: 0,
            turnout: [14, 16, 18, 17, 19, 21, 20, 22]
        ),
        DemoRunDefinition(
            id: "ts", club: club(9_100_007, "12South Social Run", members: 2_050, joined: true),
            title: "Thursday Social 5K",
            description: "The biggest social run in town. 5K at any pace, then hang out on 12th Ave.",
            host: person(18), weekday: 5, hour: 18, minute: 15,
            start: Coordinate(latitude: 36.1253, longitude: -86.7897),
            address: "12th Ave S & Paris Ave, 12South, Nashville, TN",
            routes: [DemoRoute(miles: 3.1, elevationFeet: 90, heading: 180)],
            skillLevels: 1, terrain: 1, joined: true,
            turnout: [88, 95, 101, 104, 110, 116, 121, 128]
        ),
        DemoRunDefinition(
            id: "rr", club: club(9_100_008, "Riverfront Runners", members: 470),
            title: "Monday Bridges Run",
            description: "Over the pedestrian bridge and back along the river.",
            host: person(21), weekday: 2, hour: 17, minute: 45,
            start: Coordinate(latitude: 36.1618, longitude: -86.7743),
            address: "1st Ave N & Broadway, Riverfront Park, Nashville, TN",
            routes: [DemoRoute(miles: 4.0, elevationFeet: 35, heading: 20)],
            skillLevels: 2, terrain: 0,
            turnout: [44, 41, 43, 40, 42, 39, 41, 38]
        ),
        DemoRunDefinition(
            id: "nn", club: club(9_100_009, "Nations Night Run", members: 260),
            title: "Friday Night Lights",
            description: "Short, social, and done before dinner. Reflective gear recommended.",
            host: person(24), weekday: 6, hour: 18, minute: 0,
            start: Coordinate(latitude: 36.1640, longitude: -86.8395),
            address: "51st Ave N & Centennial Blvd, The Nations, Nashville, TN",
            routes: [DemoRoute(miles: 3.0, elevationFeet: 40, heading: 90)],
            skillLevels: 1, terrain: 0,
            turnout: [18, 20, 19, 22, 24, 23, 26, 27]
        ),
        DemoRunDefinition(
            id: "cs", club: club(9_100_010, "Centennial Sunrise", members: 740, joined: true),
            title: "Saturday Sunrise Run",
            description: "Loops past the Parthenon. 10K or 5K; coffee after.",
            host: person(27), weekday: 7, hour: 7, minute: 0,
            start: Coordinate(latitude: 36.1497, longitude: -86.8120),
            address: "Parthenon steps, Centennial Park, Nashville, TN",
            routes: [DemoRoute(miles: 6.2, elevationFeet: 110, heading: 270), DemoRoute(miles: 3.1, elevationFeet: 52, heading: 270)],
            skillLevels: 3, terrain: 1,
            turnout: [52, 55, 54, 58, 57, 60, 59, 63]
        ),
        DemoRunDefinition(
            id: "sp", club: club(9_100_011, "Sylvan Park Pace Pack", members: 390),
            title: "Saturday Long Tempo",
            description: "8 miles with the middle 4 at marathon pace.",
            host: person(30), weekday: 7, hour: 7, minute: 30,
            start: Coordinate(latitude: 36.1467, longitude: -86.8430),
            address: "Murphy Rd & 46th Ave N, Sylvan Park, Nashville, TN",
            routes: [DemoRoute(miles: 8.0, elevationFeet: 180, heading: 300)],
            skillLevels: 4, terrain: 1,
            turnout: [30, 33, 31, 35, 34, 36, 35, 37]
        ),
        DemoRunDefinition(
            id: "eb", club: club(9_100_012, "East Bank Riders", members: 330, sport: "cycling"),
            title: "Saturday Coffee Ride",
            description: "No-drop social ride, 16-18 mph.",
            host: person(33), activityType: "Ride", weekday: 7, hour: 7, minute: 30,
            start: Coordinate(latitude: 36.1665, longitude: -86.7713),
            address: "Greenway trailhead, East Bank, Nashville, TN",
            routes: [DemoRoute(miles: 20.0, elevationFeet: 300, heading: 45)],
            skillLevels: 1, terrain: 1,
            turnout: [15, 17, 16, 18, 20, 19, 21, 22]
        ),
        DemoRunDefinition(
            id: "lr", club: club(9_100_013, "Sunday Long Run Co.", members: 560),
            title: "Percy Warner Long Run",
            description: "Hilly miles in Percy Warner Park. 10 or 6 miles; water at the halfway turnaround.",
            host: person(36), weekday: 1, hour: 7, minute: 0,
            start: Coordinate(latitude: 36.0703, longitude: -86.8790),
            address: "Belle Meade Blvd entrance, Percy Warner Park, Nashville, TN",
            routes: [DemoRoute(miles: 10.0, elevationFeet: 620, heading: 200), DemoRoute(miles: 6.0, elevationFeet: 380, heading: 200)],
            skillLevels: 6, terrain: 2,
            turnout: [24, 26, 29, 27, 30, 31, 33, 34]
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
        return StravaAthlete(id: 70_000_000 + index, firstName: first, lastName: last, city: "Nashville", state: "TN")
    }

    static func athletes(count: Int, seed: Int) -> [StravaAthlete] {
        (0..<count).map { person(seed + $0 * 3) }
    }

    // MARK: Geometry

    /// A wobbly closed loop of roughly `meters` that starts and ends at `start`.
    static func loop(from start: Coordinate, meters: Double, headingDegrees: Double, points: Int = 48) -> [Coordinate] {
        var radius = meters / (2 * .pi)
        var path: [Coordinate] = []
        for _ in 0..<3 {
            path = loopPath(from: start, radius: radius, headingDegrees: headingDegrees, points: points)
            let length = path.pathLength
            if length > 0 { radius *= meters / length }
        }
        return path
    }

    private static func loopPath(from start: Coordinate, radius: Double, headingDegrees: Double, points: Int) -> [Coordinate] {
        let heading = headingDegrees * .pi / 180
        // Loop center, in meters east (x) and north (y) of the start.
        let centerX = sin(heading) * radius
        let centerY = cos(heading) * radius
        let startAngle = atan2(-centerY, -centerX)
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(start.latitude * .pi / 180)
        return (0...points).map { index in
            let t = Double(index) / Double(points)
            let angle = startAngle + t * 2 * .pi
            let r = radius * (1 + 0.12 * sin(6 * .pi * t))
            let x = centerX + r * cos(angle)
            let y = centerY + r * sin(angle)
            return Coordinate(
                latitude: start.latitude + y / metersPerDegreeLatitude,
                longitude: start.longitude + x / metersPerDegreeLongitude
            )
        }
    }
}
