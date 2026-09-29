import Foundation

/// A Strava athlete as it appears in event hosts, club admins and attendee lists.
///
/// Strava trims athlete data in club contexts: admin and member lists often
/// omit `id` and profile photos and abbreviate the last name ("Peter S."),
/// so everything except the name is optional.
public struct StravaAthlete: Hashable, Sendable, Decodable {
    public let id: Int?
    public let firstName: String
    public let lastName: String
    public let profileImageURL: URL?
    public let city: String?
    public let state: String?

    public init(
        id: Int? = nil,
        firstName: String,
        lastName: String,
        profileImageURL: URL? = nil,
        city: String? = nil,
        state: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.profileImageURL = profileImageURL
        self.city = city
        self.state = state
    }

    enum CodingKeys: String, CodingKey {
        case id
        case firstname
        case lastname
        case profileMedium = "profile_medium"
        case profile
        case city
        case state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(Int.self, forKey: .id)
        firstName = container.lenient(String.self, forKey: .firstname) ?? ""
        lastName = container.lenient(String.self, forKey: .lastname) ?? ""
        profileImageURL = container.lenientURL(forKey: .profileMedium) ?? container.lenientURL(forKey: .profile)
        city = container.lenient(String.self, forKey: .city)
        state = container.lenient(String.self, forKey: .state)
    }

    /// "Maya R." style name, matching how Strava shows other athletes.
    public var displayName: String {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        switch (first.isEmpty, last.isEmpty) {
        case (true, true):
            return "Strava athlete"
        case (false, true):
            return first
        case (true, false):
            return last
        case (false, false):
            let lastInitial = last.hasSuffix(".") ? last : "\(last.prefix(1))."
            return "\(first) \(lastInitial)"
        }
    }

    public var initials: String {
        let letters = [firstName.first, lastName.first].compactMap { $0 }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
