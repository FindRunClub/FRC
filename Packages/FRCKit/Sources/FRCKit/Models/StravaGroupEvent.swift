import Foundation

/// A club group event from `GET /clubs/{id}/group_events`.
///
/// Field names follow real responses captured in 2026 (the endpoint is not in
/// Strava's published reference). Notable quirks:
/// - `id` and `route_id` can exceed 2^53, hence `StravaID`.
/// - `upcoming_occurrences` often lists only the next date of a recurring event.
/// - `frequency` / `days_of_week` only come back from `GET /group_events/{id}`.
public struct StravaGroupEvent: Identifiable, Hashable, Sendable, Decodable {
    public let id: StravaID
    public let title: String
    public let eventDescription: String?
    public let clubID: Int?
    public let organizingAthlete: StravaAthlete?
    /// Strava activity type, e.g. "Run", "TrailRun", "Ride".
    public let activityType: String?
    public let route: StravaRoute?
    public let womenOnly: Bool
    public let isPrivate: Bool
    /// Bitmask: 1 = casual/no-drop, 2 = tempo, 4 = race pace. `nil` when the event uses pace groups.
    public let skillLevels: Int?
    /// 0 = mostly flat, 1 = rolling hills, 2 = killer climbs.
    public let terrain: Int?
    public let upcomingOccurrences: [Date]
    /// IANA identifier such as "America/New_York".
    public let timeZoneIdentifier: String?
    public let address: String?
    /// Whether the signed-in athlete has joined.
    public let joined: Bool
    public let startCoordinate: Coordinate?
    public let frequency: String?
    public let daysOfWeek: [String]?

    public init(
        id: StravaID,
        title: String,
        eventDescription: String? = nil,
        clubID: Int? = nil,
        organizingAthlete: StravaAthlete? = nil,
        activityType: String? = "Run",
        route: StravaRoute? = nil,
        womenOnly: Bool = false,
        isPrivate: Bool = false,
        skillLevels: Int? = nil,
        terrain: Int? = nil,
        upcomingOccurrences: [Date],
        timeZoneIdentifier: String? = nil,
        address: String? = nil,
        joined: Bool = false,
        startCoordinate: Coordinate? = nil,
        frequency: String? = nil,
        daysOfWeek: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.eventDescription = eventDescription
        self.clubID = clubID
        self.organizingAthlete = organizingAthlete
        self.activityType = activityType
        self.route = route
        self.womenOnly = womenOnly
        self.isPrivate = isPrivate
        self.skillLevels = skillLevels
        self.terrain = terrain
        self.upcomingOccurrences = upcomingOccurrences
        self.timeZoneIdentifier = timeZoneIdentifier
        self.address = address
        self.joined = joined
        self.startCoordinate = startCoordinate
        self.frequency = frequency
        self.daysOfWeek = daysOfWeek
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case clubID = "club_id"
        case club
        case organizingAthlete = "organizing_athlete"
        case activityType = "activity_type"
        case routeID = "route_id"
        case route
        case womenOnly = "women_only"
        case isPrivate = "private"
        case skillLevels = "skill_levels"
        case terrain
        case upcomingOccurrences = "upcoming_occurrences"
        case zone
        case address
        case joined
        case startLatLng = "start_latlng"
        case frequency
        case daysOfWeek = "days_of_week"
    }

    enum EmbeddedClubKeys: String, CodingKey {
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(StravaID.self, forKey: .id)

        let rawTitle = container.lenient(String.self, forKey: .title)?.trimmingCharacters(in: .whitespacesAndNewlines)
        title = (rawTitle?.isEmpty == false ? rawTitle : nil) ?? "Club event"

        let rawDescription = container.lenient(String.self, forKey: .description)?.trimmingCharacters(in: .whitespacesAndNewlines)
        eventDescription = rawDescription?.isEmpty == false ? rawDescription : nil

        let embeddedClub = try? container.nestedContainer(keyedBy: EmbeddedClubKeys.self, forKey: .club)
        clubID = container.lenient(Int.self, forKey: .clubID) ?? embeddedClub?.lenient(Int.self, forKey: .id)

        organizingAthlete = container.lenient(StravaAthlete.self, forKey: .organizingAthlete)
        activityType = container.lenient(String.self, forKey: .activityType)

        // The embedded route summary carries the name and polyline. If only a
        // bare `route_id` is present, keep the ID so details can be fetched later.
        if let embeddedRoute = container.lenient(StravaRoute.self, forKey: .route) {
            route = embeddedRoute.id == nil
                ? embeddedRoute.merged(with: StravaRoute(id: container.lenient(StravaID.self, forKey: .routeID)))
                : embeddedRoute
        } else if let routeID = container.lenient(StravaID.self, forKey: .routeID) {
            route = StravaRoute(id: routeID)
        } else {
            route = nil
        }

        womenOnly = container.lenient(Bool.self, forKey: .womenOnly) ?? false
        isPrivate = container.lenient(Bool.self, forKey: .isPrivate) ?? false
        skillLevels = container.lenient(Int.self, forKey: .skillLevels)
        terrain = container.lenient(Int.self, forKey: .terrain)

        let occurrenceStrings = container.lenient([String].self, forKey: .upcomingOccurrences) ?? []
        upcomingOccurrences = occurrenceStrings.compactMap(StravaDateParser.parse).sorted()

        timeZoneIdentifier = container.lenient(String.self, forKey: .zone)
        let rawAddress = container.lenient(String.self, forKey: .address)?.trimmingCharacters(in: .whitespacesAndNewlines)
        address = rawAddress?.isEmpty == false ? rawAddress : nil
        joined = container.lenient(Bool.self, forKey: .joined) ?? false
        startCoordinate = Coordinate(latLng: container.lenient([Double].self, forKey: .startLatLng))
        frequency = container.lenient(String.self, forKey: .frequency)
        daysOfWeek = container.lenient([String].self, forKey: .daysOfWeek)
    }
}

// MARK: - Derived values

extension StravaGroupEvent {
    /// Activity types treated as runs by the "Runs only" filter.
    public static let runActivityTypes: Set<String> = ["run", "trailrun", "virtualrun"]

    /// Events without an activity type are treated as runs rather than hidden.
    public var isRun: Bool {
        guard let activityType else { return true }
        return Self.runActivityTypes.contains(activityType.lowercased())
    }

    public var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    public var stravaURL: URL {
        if let clubID {
            return URL(string: "https://www.strava.com/clubs/\(clubID)/group_events/\(id.rawValue)")!
        }
        return URL(string: "https://www.strava.com/group_events/\(id.rawValue)")!
    }

    public var skillLevelLabel: String? {
        guard let skillLevels, skillLevels > 0 else { return nil }
        let labels = [(1, "Casual (no drop)"), (2, "Tempo"), (4, "Race pace")]
            .filter { (skillLevels & $0.0) != 0 }
            .map { $0.1 }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    public var terrainLabel: String? {
        switch terrain {
        case 0: return "Mostly flat"
        case 1: return "Rolling hills"
        case 2: return "Killer climbs"
        default: return nil
        }
    }

    /// "Weekly on Tuesday" when Strava includes recurrence details.
    public var recurrenceLabel: String? {
        guard let frequency, frequency != "no_repeat" else { return nil }
        let cadence = frequency.replacingOccurrences(of: "_", with: " ").capitalized
        guard let days = daysOfWeek, !days.isEmpty else { return cadence }
        return "\(cadence) on \(days.map { $0.capitalized }.joined(separator: ", "))"
    }

    /// Human-readable activity type ("TrailRun" -> "Trail Run").
    public var activityLabel: String {
        guard let activityType, !activityType.isEmpty else { return "Run" }
        var label = ""
        for character in activityType {
            if character.isUppercase, !label.isEmpty { label.append(" ") }
            label.append(character)
        }
        return label
    }
}
