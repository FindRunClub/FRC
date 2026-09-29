import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where tokens are persisted between launches (the app uses the Keychain).
public protocol StravaTokenStorage: Sendable {
    func loadTokens() -> StravaTokens?
    func saveTokens(_ tokens: StravaTokens?)
}

/// Owns the signed-in athlete's tokens: exchanges the OAuth code, refreshes
/// before expiry (one refresh at a time), and signs out.
public actor StravaSession: StravaAccessTokenProviding {
    private let credentials: StravaAppCredentials
    private let transport: HTTPTransport
    private let storage: StravaTokenStorage
    private let now: @Sendable () -> Date
    private var tokens: StravaTokens?
    private var refreshTask: Task<StravaTokens, Error>?

    public init(
        credentials: StravaAppCredentials,
        storage: StravaTokenStorage,
        transport: HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.storage = storage
        self.transport = transport
        self.now = now
        self.tokens = storage.loadTokens()
    }

    public var currentTokens: StravaTokens? { tokens }

    public func accessToken(forceRefresh: Bool) async throws -> String {
        guard let tokens else { throw StravaAPIError.notSignedIn }
        if !forceRefresh && !tokens.needsRefresh(now: now()) {
            return tokens.accessToken
        }
        return try await refresh().accessToken
    }

    /// Completes sign-in with the code from the OAuth redirect.
    @discardableResult
    public func signIn(authorizationCode code: String) async throws -> StravaTokens {
        do {
            let newTokens = try await requestTokens(grant: .authorizationCode(code), previous: nil)
            store(newTokens)
            return newTokens
        } catch StravaAPIError.unauthorized {
            // A bad Client ID/Secret or an expired code both come back as 400/401.
            throw StravaAuthError.authorizationFailed("Strava rejected the sign-in. Check the Client ID and Secret in Config/Secrets.xcconfig.")
        }
    }

    /// Forgets the tokens and asks Strava to revoke the app's access.
    public func signOut() async {
        let revoked = tokens
        refreshTask?.cancel()
        refreshTask = nil
        store(nil)
        if let revoked {
            var request = URLRequest(url: StravaOAuth.deauthorizeURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(revoked.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await transport.send(request)
        }
    }

    private func refresh() async throws -> StravaTokens {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let current = tokens else { throw StravaAPIError.notSignedIn }

        let task = Task { try await self.requestTokens(grant: .refreshToken(current.refreshToken), previous: current) }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let refreshed = try await task.value
            // The athlete may have signed out while the refresh was in flight.
            guard tokens != nil else { throw StravaAPIError.notSignedIn }
            store(refreshed)
            return refreshed
        } catch StravaAPIError.unauthorized {
            // The refresh token was revoked (e.g. the athlete disconnected the app on strava.com).
            store(nil)
            throw StravaAPIError.unauthorized
        }
    }

    private func requestTokens(grant: StravaOAuth.Grant, previous: StravaTokens?) async throws -> StravaTokens {
        let request = StravaOAuth.tokenRequest(for: credentials, grant: grant)
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300:
            return try StravaOAuth.tokens(from: data, previous: previous)
        case 400, 401:
            // Strava answers an invalid code or refresh token with 400 or 401.
            throw StravaAPIError.unauthorized
        default:
            throw StravaAPIError(status: response.statusCode, body: data)
        }
    }

    private func store(_ newTokens: StravaTokens?) {
        tokens = newTokens
        storage.saveTokens(newTokens)
    }
}
