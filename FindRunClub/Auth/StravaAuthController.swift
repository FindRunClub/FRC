import AuthenticationServices
import FRCKit
import Foundation
import Observation

/// Drives "Connect with Strava": the OAuth web sheet, the code exchange,
/// and sign-out. Tokens live in the Keychain via `StravaSession`.
@MainActor
@Observable
final class StravaAuthController {
    enum State: Equatable {
        /// No Client ID/Secret in this build; the app runs on demo data.
        case notConfigured
        case signedOut
        case signingIn
        case signedIn(athleteName: String)
    }

    private(set) var state: State
    private(set) var lastError: String?

    let session: StravaSession?
    private let credentials: StravaAppCredentials?
    private let webAuthenticator = WebAuthenticator()

    init(config: AppConfig) {
        guard let credentials = config.stravaCredentials else {
            self.credentials = nil
            self.session = nil
            self.state = .notConfigured
            return
        }
        let storage = KeychainTokenStorage()
        self.credentials = credentials
        self.session = StravaSession(credentials: credentials, storage: storage)
        if let tokens = storage.loadTokens() {
            state = .signedIn(athleteName: tokens.athlete?.displayName ?? "Strava athlete")
        } else {
            state = .signedOut
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    func signIn() async {
        guard let credentials, let session, let callbackScheme = credentials.callbackURLScheme else {
            lastError = StravaAuthError.notConfigured.localizedDescription
            return
        }
        lastError = nil
        state = .signingIn

        let requestState = UUID().uuidString
        do {
            let callbackURL = try await webAuthenticator.authenticate(
                url: StravaOAuth.authorizationURL(for: credentials, state: requestState),
                callbackURLScheme: callbackScheme
            )
            let code = try StravaOAuth.authorizationCode(fromCallback: callbackURL, expectedState: requestState)
            let tokens = try await session.signIn(authorizationCode: code)
            state = .signedIn(athleteName: tokens.athlete?.displayName ?? "Strava athlete")
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            state = .signedOut
        } catch {
            state = .signedOut
            lastError = error.localizedDescription
        }
    }

    func signOut() async {
        await session?.signOut()
        lastError = nil
        state = credentials == nil ? .notConfigured : .signedOut
    }

    /// Called when Strava rejects the saved session (e.g. access was revoked on strava.com).
    func handleSessionEnded() async {
        guard let session, await session.currentTokens == nil else { return }
        state = .signedOut
        lastError = StravaAPIError.unauthorized.localizedDescription
    }
}
