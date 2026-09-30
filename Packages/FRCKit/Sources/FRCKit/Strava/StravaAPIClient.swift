import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supplies a valid access token, refreshing it when needed.
public protocol StravaAccessTokenProviding: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
}

/// Thin typed wrapper over the Strava v3 endpoints the app uses.
///
/// Rate limits (default app tier): 200 requests / 15 min and 2,000 / day,
/// with reads capped at 100 / 15 min and 1,000 / day. Callers should load
/// details lazily and cache what they can.
public struct StravaAPIClient: Sendable {
    public static let baseURL = URL(string: "https://www.strava.com/api/v3")!

    private let transport: HTTPTransport
    private let tokens: StravaAccessTokenProviding

    public init(transport: HTTPTransport = URLSessionTransport(), tokens: StravaAccessTokenProviding) {
        self.transport = transport
        self.tokens = tokens
    }

    /// `GET /athlete/clubs`: clubs the signed-in athlete belongs to.
    public func athleteClubs() async throws -> [StravaClub] {
        let page: LossyArray<StravaClub> = try await get("athlete/clubs", query: ["page": "1", "per_page": "200"])
        return page.elements
    }

    /// `GET /clubs/{id}`: one club's details, used when adding a club by link.
    public func club(_ link: StravaClubLink) async throws -> StravaClub {
        try await get("clubs/\(link.pathComponent)")
    }

    /// `GET /clubs/{id}/group_events`: upcoming events for a club.
    /// Not in Strava's published reference, but used by current third-party apps.
    public func upcomingGroupEvents(clubID: Int) async throws -> [StravaGroupEvent] {
        let page: LossyArray<StravaGroupEvent> = try await get(
            "clubs/\(clubID)/group_events",
            query: ["upcoming": "true", "page": "1", "per_page": "100"]
        )
        return page.elements
    }

    /// `GET /clubs/{id}/admins`
    public func clubAdmins(clubID: Int) async throws -> [StravaAthlete] {
        let page: LossyArray<StravaAthlete> = try await get("clubs/\(clubID)/admins", query: ["page": "1", "per_page": "100"])
        return page.elements
    }

    /// `GET /group_events/{id}/athletes`: athletes who joined the next occurrence.
    /// Undocumented; callers should treat failures as "count unavailable".
    public func groupEventAthletes(eventID: StravaID, maxPages: Int = 5) async throws -> [StravaAthlete] {
        let perPage = 100
        var athletes: [StravaAthlete] = []
        for pageNumber in 1...max(maxPages, 1) {
            let page: LossyArray<StravaAthlete> = try await get(
                "group_events/\(eventID.rawValue)/athletes",
                query: ["page": String(pageNumber), "per_page": String(perPage)]
            )
            athletes += page.elements
            if page.rawCount < perPage { break }
        }
        return athletes
    }

    /// `GET /routes/{id}`: full route with distance, elevation and polyline.
    public func route(id: StravaID) async throws -> StravaRoute {
        try await get("routes/\(id.rawValue)")
    }

    // MARK: - Plumbing

    private func get<Response: Decodable>(_ path: String, query: KeyValuePairs<String, String> = [:]) async throws -> Response {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw StravaAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // One retry with a forced refresh covers a token revoked or expired early.
        var token = try await tokens.accessToken(forceRefresh: false)
        for attempt in 0..<2 {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300:
                do {
                    return try JSONDecoder().decode(Response.self, from: data)
                } catch {
                    throw StravaAPIError.decodingFailed(String(describing: error))
                }
            case 401 where attempt == 0:
                token = try await tokens.accessToken(forceRefresh: true)
            default:
                throw StravaAPIError(status: response.statusCode, body: data)
            }
        }
        throw StravaAPIError.unauthorized
    }
}
