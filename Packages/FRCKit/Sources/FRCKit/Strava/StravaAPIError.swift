import Foundation

public enum StravaAPIError: Error, Equatable, Sendable {
    case notSignedIn
    /// The access token was rejected and could not be refreshed.
    case unauthorized
    /// Missing scope, or a private resource the athlete can't see.
    case forbidden
    case notFound
    /// Strava's 15-minute or daily request limit was hit.
    case rateLimited
    case http(status: Int, message: String?)
    case invalidResponse
    case decodingFailed(String)

    init(status: Int, body: Data) {
        switch status {
        case 401: self = .unauthorized
        case 403: self = .forbidden
        case 404: self = .notFound
        case 429: self = .rateLimited
        default:
            let fault = try? JSONDecoder().decode(StravaFault.self, from: body)
            self = .http(status: status, message: fault?.message)
        }
    }
}

extension StravaAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Connect your Strava account to see your clubs' events."
        case .unauthorized:
            return "Your Strava session expired. Please reconnect Strava."
        case .forbidden:
            return "Strava didn't allow access to this data."
        case .notFound:
            return "Strava couldn't find this item."
        case .rateLimited:
            return "Strava's request limit was reached. Try again in about 15 minutes."
        case .http(let status, let message):
            return "Strava returned an error (\(status))\(message.map { ": \($0)" } ?? ".")"
        case .invalidResponse:
            return "Strava sent an unexpected response."
        case .decodingFailed:
            return "Strava sent data this version of the app can't read."
        }
    }
}

public enum StravaAuthError: Error, Equatable, Sendable {
    case notConfigured
    case accessDenied
    case stateMismatch
    case missingCode
    case authorizationFailed(String)
}

extension StravaAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Strava isn't configured. Add a Client ID and Secret in Config/Secrets.xcconfig."
        case .accessDenied:
            return "Strava access was declined."
        case .stateMismatch:
            return "The Strava sign-in response didn't match this request. Please try again."
        case .missingCode:
            return "Strava didn't return an authorization code."
        case .authorizationFailed(let reason):
            return "Strava sign-in failed: \(reason)"
        }
    }
}

/// Strava's error body: {"message": "...", "errors": [...]}
struct StravaFault: Decodable {
    let message: String?
}
