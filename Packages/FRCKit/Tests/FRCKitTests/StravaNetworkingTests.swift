import XCTest
@testable import FRCKit

/// Records requests and answers them with canned responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Responder = (URLRequest) throws -> (status: Int, body: String)

    private let lock = NSLock()
    private let responder: Responder
    private var recorded: [URLRequest] = []

    init(_ responder: @escaping Responder) {
        self.responder = responder
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let (status, body) = try responder(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

final class InMemoryTokenStorage: StravaTokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: StravaTokens?

    init(_ tokens: StravaTokens? = nil) {
        self.tokens = tokens
    }

    func loadTokens() -> StravaTokens? {
        lock.withLock { tokens }
    }

    func saveTokens(_ tokens: StravaTokens?) {
        lock.withLock { self.tokens = tokens }
    }
}

private extension URLRequest {
    var formParameters: [String: String] {
        let body = String(decoding: httpBody ?? Data(), as: UTF8.self)
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    var bearerToken: String? {
        value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
    }
}

final class StravaOAuthTests: XCTestCase {
    private let credentials = StravaAppCredentials(
        clientID: "12345",
        clientSecret: "s3cr3t+/=",
        redirectURI: "findrunclub://localhost",
        scope: "read"
    )

    func testAuthorizationURL() throws {
        let url = StravaOAuth.authorizationURL(for: credentials, state: "abc")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "www.strava.com")
        XCTAssertEqual(components.path, "/oauth/mobile/authorize")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["client_id"], "12345")
        XCTAssertEqual(query["redirect_uri"], "findrunclub://localhost")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["scope"], "read")
        XCTAssertEqual(query["state"], "abc")
        XCTAssertEqual(credentials.callbackURLScheme, "findrunclub")
    }

    func testAuthorizationCallbackParsing() throws {
        let success = URL(string: "findrunclub://localhost?state=abc&code=the-code&scope=read")!
        XCTAssertEqual(try StravaOAuth.authorizationCode(fromCallback: success, expectedState: "abc"), "the-code")

        let denied = URL(string: "findrunclub://localhost?state=abc&error=access_denied")!
        XCTAssertThrowsError(try StravaOAuth.authorizationCode(fromCallback: denied, expectedState: "abc")) {
            XCTAssertEqual($0 as? StravaAuthError, .accessDenied)
        }

        let forged = URL(string: "findrunclub://localhost?state=zzz&code=the-code")!
        XCTAssertThrowsError(try StravaOAuth.authorizationCode(fromCallback: forged, expectedState: "abc")) {
            XCTAssertEqual($0 as? StravaAuthError, .stateMismatch)
        }
    }

    func testTokenRequestsAreFormEncoded() {
        let exchange = StravaOAuth.tokenRequest(for: credentials, grant: .authorizationCode("the-code"))
        XCTAssertEqual(exchange.httpMethod, "POST")
        XCTAssertEqual(exchange.url, StravaOAuth.tokenURL)
        XCTAssertEqual(exchange.formParameters, [
            "client_id": "12345",
            "client_secret": "s3cr3t+/=",
            "code": "the-code",
            "grant_type": "authorization_code",
        ])

        let refresh = StravaOAuth.tokenRequest(for: credentials, grant: .refreshToken("r-1"))
        XCTAssertEqual(refresh.formParameters["grant_type"], "refresh_token")
        XCTAssertEqual(refresh.formParameters["refresh_token"], "r-1")
    }

    func testTokenResponsesKeepTheAthleteAcrossRefreshes() throws {
        let initial = try StravaOAuth.tokens(from: Data(Fixtures.tokenExchange.utf8), previous: nil)
        XCTAssertEqual(initial.accessToken, "access-1")
        XCTAssertEqual(initial.refreshToken, "refresh-1")
        XCTAssertEqual(initial.expiresAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(initial.athlete?.firstName, "Valera")

        let refreshed = try StravaOAuth.tokens(from: Data(Fixtures.tokenRefresh.utf8), previous: initial)
        XCTAssertEqual(refreshed.accessToken, "access-2")
        XCTAssertEqual(refreshed.athlete, initial.athlete)
    }
}

final class StravaClientTests: XCTestCase {
    private let credentials = StravaAppCredentials(clientID: "1", clientSecret: "s", redirectURI: "findrunclub://localhost")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeSession(tokensExpiringIn seconds: TimeInterval, transport: MockTransport) -> (StravaSession, InMemoryTokenStorage) {
        let storage = InMemoryTokenStorage(StravaTokens(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(seconds)
        ))
        let fixedNow = now
        return (StravaSession(credentials: credentials, storage: storage, transport: transport, now: { fixedNow }), storage)
    }

    func testExpiredTokenIsRefreshedBeforeCallingTheAPI() async throws {
        let transport = MockTransport { request in
            if request.url?.path == "/oauth/token" {
                return (200, Fixtures.tokenRefresh)
            }
            XCTAssertEqual(request.bearerToken, "access-2")
            return (200, Fixtures.athleteClubs)
        }
        let (session, storage) = makeSession(tokensExpiringIn: 30, transport: transport)
        let client = StravaAPIClient(transport: transport, tokens: session)

        let clubs = try await client.athleteClubs()

        XCTAssertEqual(clubs.map(\.id), [1752189])
        XCTAssertEqual(transport.requests.first?.formParameters["refresh_token"], "old-refresh")
        XCTAssertEqual(storage.loadTokens()?.accessToken, "access-2", "Refreshed tokens are persisted")
    }

    func testRejectedTokenIsRefreshedAndRetriedOnce() async throws {
        let transport = MockTransport { request in
            switch (request.url?.path, request.bearerToken) {
            case ("/oauth/token", _):
                return (200, Fixtures.tokenRefresh)
            case (_, "old-access"):
                return (401, #"{"message":"Authorization Error"}"#)
            default:
                return (200, "[]")
            }
        }
        let (session, _) = makeSession(tokensExpiringIn: 3_600, transport: transport)
        let client = StravaAPIClient(transport: transport, tokens: session)

        let events = try await client.upcomingGroupEvents(clubID: 55)

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(transport.requests.count, 3)
        let eventsRequest = try XCTUnwrap(transport.requests.last?.url)
        XCTAssertEqual(eventsRequest.path, "/api/v3/clubs/55/group_events")
        XCTAssertTrue(eventsRequest.query?.contains("upcoming=true") ?? false)
    }

    func testRevokedRefreshTokenSignsOut() async throws {
        let transport = MockTransport { _ in (400, #"{"message":"Bad Request"}"#) }
        let (session, storage) = makeSession(tokensExpiringIn: -10, transport: transport)
        let client = StravaAPIClient(transport: transport, tokens: session)

        do {
            _ = try await client.athleteClubs()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StravaAPIError, .unauthorized)
        }
        XCTAssertNil(storage.loadTokens())
        let tokensAfter = await session.currentTokens
        XCTAssertNil(tokensAfter)
    }

    func testHTTPErrorsMapToFriendlyCases() async throws {
        let transport = MockTransport { _ in (429, #"{"message":"Rate Limit Exceeded"}"#) }
        let (session, _) = makeSession(tokensExpiringIn: 3_600, transport: transport)
        let client = StravaAPIClient(transport: transport, tokens: session)

        do {
            _ = try await client.clubAdmins(clubID: 1)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StravaAPIError, .rateLimited)
        }
    }

    func testDataSourceKeepsGoingWhenOneClubFails() async throws {
        let transport = MockTransport { request in
            switch request.url?.path {
            case "/api/v3/athlete/clubs":
                return (200, #"[{"id": 1, "name": "Open Club"}, {"id": 2, "name": "Locked Club"}]"#)
            case "/api/v3/clubs/1/group_events":
                return (200, Fixtures.clubEventsList)
            case "/api/v3/clubs/2/group_events":
                return (403, #"{"message":"Forbidden"}"#)
            default:
                return (404, "{}")
            }
        }
        let (session, _) = makeSession(tokensExpiringIn: 3_600, transport: transport)
        let source = StravaClubEventsDataSource(client: StravaAPIClient(transport: transport, tokens: session))

        let snapshot = try await source.loadClubEvents()

        XCTAssertEqual(snapshot.clubs.map(\.name), ["Locked Club", "Open Club"])
        XCTAssertEqual(snapshot.events.count, 2)
        XCTAssertTrue(snapshot.events.allSatisfy { $0.club.id == 1 })
        XCTAssertEqual(snapshot.failures.map(\.club.id), [2])
    }

    func testDataSourceSurfacesSessionErrors() async throws {
        let transport = MockTransport { _ in (401, "{}") }
        let storage = InMemoryTokenStorage(nil)
        let session = StravaSession(credentials: credentials, storage: storage, transport: transport)
        let source = StravaClubEventsDataSource(client: StravaAPIClient(transport: transport, tokens: session))

        do {
            _ = try await source.loadClubEvents()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StravaAPIError, .notSignedIn)
        }
        XCTAssertTrue(transport.requests.isEmpty, "No network calls without tokens")
    }
}
