import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The values from your Strava API application (strava.com/settings/api).
public struct StravaAppCredentials: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String
    /// Must use a host that matches the app's "Authorization Callback Domain"
    /// (`localhost` is always allowed by Strava).
    public let redirectURI: String
    public let scope: String

    public init(clientID: String, clientSecret: String, redirectURI: String, scope: String = "read") {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scope = scope
    }

    public var callbackURLScheme: String? {
        URL(string: redirectURI)?.scheme
    }
}

/// Access + refresh tokens. Access tokens last six hours.
public struct StravaTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var athlete: Athlete?

    public struct Athlete: Codable, Sendable, Equatable {
        public var id: Int?
        public var firstName: String
        public var lastName: String
        public var profileImageURL: URL?

        public var displayName: String {
            let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Strava athlete" : name
        }
    }

    public init(accessToken: String, refreshToken: String, expiresAt: Date, athlete: Athlete? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.athlete = athlete
    }

    /// True shortly before expiry so requests never race the deadline.
    public func needsRefresh(now: Date, leeway: TimeInterval = 120) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}

public enum StravaOAuth {
    /// Strava's mobile-friendly consent page, shown in an in-app browser sheet.
    public static let authorizeURL = URL(string: "https://www.strava.com/oauth/mobile/authorize")!
    public static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    public static let deauthorizeURL = URL(string: "https://www.strava.com/oauth/deauthorize")!

    public enum Grant: Sendable, Equatable {
        case authorizationCode(String)
        case refreshToken(String)
    }

    public static func authorizationURL(for credentials: StravaAppCredentials, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: credentials.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: credentials.scope),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Pulls the authorization code out of the redirect Strava sends back.
    public static func authorizationCode(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let error = value("error") {
            throw error == "access_denied" ? StravaAuthError.accessDenied : StravaAuthError.authorizationFailed(error)
        }
        guard value("state") == expectedState else {
            throw StravaAuthError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw StravaAuthError.missingCode
        }
        return code
    }

    public static func tokenRequest(for credentials: StravaAppCredentials, grant: Grant) -> URLRequest {
        var parameters = [
            ("client_id", credentials.clientID),
            ("client_secret", credentials.clientSecret),
        ]
        switch grant {
        case .authorizationCode(let code):
            parameters += [("code", code), ("grant_type", "authorization_code")]
        case .refreshToken(let refreshToken):
            parameters += [("refresh_token", refreshToken), ("grant_type", "refresh_token")]
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncoded(parameters)
        return request
    }

    /// Decodes a token response. Refresh responses omit the athlete, so the
    /// previous one is carried over.
    public static func tokens(from data: Data, previous: StravaTokens?) throws -> StravaTokens {
        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw StravaAPIError.decodingFailed(String(describing: error))
        }
        let athlete = response.athlete.map {
            StravaTokens.Athlete(id: $0.id, firstName: $0.firstName, lastName: $0.lastName, profileImageURL: $0.profileImageURL)
        }
        return StravaTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date(timeIntervalSince1970: response.expiresAt),
            athlete: athlete ?? previous?.athlete
        )
    }

    static func formEncoded(_ parameters: [(String, String)]) -> Data {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = parameters
            .map { name, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
        let athlete: StravaAthlete?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case athlete
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try container.decode(String.self, forKey: .accessToken)
            refreshToken = try container.decode(String.self, forKey: .refreshToken)
            expiresAt = try container.decode(TimeInterval.self, forKey: .expiresAt)
            athlete = container.lenient(StravaAthlete.self, forKey: .athlete)
        }
    }
}
