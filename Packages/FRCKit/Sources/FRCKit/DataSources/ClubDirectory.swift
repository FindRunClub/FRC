import Foundation

/// FRC's list of Strava clubs per city, so runners see every club in their
/// area, not only the ones they've joined. Strava's API has no way to search
/// clubs by location, so this list is curated (bundled with the app, updatable
/// from a hosted JSON file) and runners can add clubs by pasting a link.
public struct ClubDirectory: Codable, Hashable, Sendable {
    public var areas: [Area]

    public init(areas: [Area]) {
        self.areas = areas
    }

    public struct Area: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        /// "Nashville, TN"
        public let name: String
        public let latitude: Double
        public let longitude: Double
        public var clubs: [Entry]

        public init(id: String, name: String, latitude: Double, longitude: Double, clubs: [Entry]) {
            self.id = id
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.clubs = clubs
        }

        public var center: Coordinate {
            Coordinate(latitude: latitude, longitude: longitude)
        }
    }

    /// One Strava club. Only `id` is required; the rest saves a request per club.
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let city: String?
        public let state: String?

        public init(id: Int, name: String, city: String? = nil, state: String? = nil) {
            self.id = id
            self.name = name
            self.city = city
            self.state = state
        }

        public init(club: StravaClub) {
            self.init(id: club.id, name: club.name, city: club.city, state: club.state)
        }

        public var club: StravaClub {
            StravaClub(id: id, name: name, city: city, state: state)
        }
    }

    /// The area whose center is closest to `location`, or the first area.
    public func nearestArea(to location: Coordinate?) -> Area? {
        guard let location else { return areas.first }
        return areas.min { $0.center.distance(to: location) < $1.center.distance(to: location) }
    }

    public static func decode(_ data: Data) throws -> ClubDirectory {
        try JSONDecoder().decode(ClubDirectory.self, from: data)
    }
}

/// Reads a club reference from what a runner pastes: a Strava club link,
/// "strava.com/clubs/123456", or just the number.
public enum StravaClubLink: Hashable, Sendable {
    case id(Int)
    /// A vanity link such as strava.com/clubs/five-points-rc.
    case slug(String)

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed), id > 0 {
            self = .id(id)
            return
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let host = url.host?.lowercased(),
              host == "strava.com" || host.hasSuffix(".strava.com")
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(of: "clubs"), index + 1 < parts.count else { return nil }
        let value = parts[index + 1]
        if let id = Int(value), id > 0 {
            self = .id(id)
        } else if !value.isEmpty {
            self = .slug(value)
        } else {
            return nil
        }
    }

    /// The path segment for `GET /clubs/{id}`.
    public var pathComponent: String {
        switch self {
        case .id(let id): return String(id)
        case .slug(let slug): return slug
        }
    }
}
