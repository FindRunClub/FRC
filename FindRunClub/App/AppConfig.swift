import FRCKit
import Foundation

/// Build-time settings read from Info.plist, which gets them from
/// Config/FindRunClub.xcconfig and your untracked Config/Secrets.xcconfig.
struct AppConfig {
    /// Strava only checks the host, which must match your API app's
    /// "Authorization Callback Domain". `localhost` is always allowed.
    static let stravaRedirectURI = "findrunclub://localhost"

    let stravaCredentials: StravaAppCredentials?
    /// Hosted copy of the club directory, refreshed on launch.
    let clubDirectoryURL: URL?

    static let current = AppConfig(infoDictionary: Bundle.main.infoDictionary ?? [:])

    init(infoDictionary: [String: Any]) {
        let clientID = Self.value("StravaClientID", in: infoDictionary)
        let clientSecret = Self.value("StravaClientSecret", in: infoDictionary)
        if let clientID, let clientSecret {
            stravaCredentials = StravaAppCredentials(
                clientID: clientID,
                clientSecret: clientSecret,
                redirectURI: Self.stravaRedirectURI,
                scope: "read"
            )
        } else {
            stravaCredentials = nil
        }
        clubDirectoryURL = Self.value("ClubDirectoryURL", in: infoDictionary).flatMap(URL.init(string:))
    }

    /// Returns nil for blanks and unexpanded build settings like "$(STRAVA_CLIENT_ID)".
    private static func value(_ key: String, in infoDictionary: [String: Any]) -> String? {
        guard let raw = infoDictionary[key] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$("), !value.uppercased().contains("YOUR_") else { return nil }
        return value
    }
}
