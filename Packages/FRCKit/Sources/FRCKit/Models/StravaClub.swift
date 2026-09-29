import Foundation

/// A Strava club, from `GET /athlete/clubs` or embedded in an event.
public struct StravaClub: Identifiable, Hashable, Sendable, Decodable {
    public let id: Int
    public let name: String
    public let profileImageURL: URL?
    public let sportType: String?
    public let city: String?
    public let state: String?
    public let country: String?
    public let memberCount: Int?
    /// Vanity slug for strava.com/clubs/<slug>.
    public let urlSlug: String?
    public let isPrivate: Bool

    public init(
        id: Int,
        name: String,
        profileImageURL: URL? = nil,
        sportType: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        memberCount: Int? = nil,
        urlSlug: String? = nil,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.profileImageURL = profileImageURL
        self.sportType = sportType
        self.city = city
        self.state = state
        self.country = country
        self.memberCount = memberCount
        self.urlSlug = urlSlug
        self.isPrivate = isPrivate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profileMedium = "profile_medium"
        case profile
        case sportType = "sport_type"
        case city
        case state
        case country
        case memberCount = "member_count"
        case url
        case isPrivate = "private"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.lenient(String.self, forKey: .name) ?? "Club \(id)"
        profileImageURL = container.lenientURL(forKey: .profileMedium) ?? container.lenientURL(forKey: .profile)
        sportType = container.lenient(String.self, forKey: .sportType)
        city = container.lenient(String.self, forKey: .city)
        state = container.lenient(String.self, forKey: .state)
        country = container.lenient(String.self, forKey: .country)
        memberCount = container.lenient(Int.self, forKey: .memberCount)
        urlSlug = container.lenient(String.self, forKey: .url)
        isPrivate = container.lenient(Bool.self, forKey: .isPrivate) ?? false
    }

    public var stravaURL: URL {
        URL(string: "https://www.strava.com/clubs/\(urlSlug ?? String(id))")!
    }

    public var locationDescription: String? {
        let parts = [city, state].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
