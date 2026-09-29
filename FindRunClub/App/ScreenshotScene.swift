#if DEBUG
import Foundation

/// Debug-only hooks that let `scripts/capture-screenshots.sh` (run in CI)
/// open a specific screen via launch arguments, e.g.
/// `-FRCScreenshotScene filters -FRCScreenshotWeekday 3`.
struct ScreenshotScene {
    enum Screen: String {
        case map
        case expanded
        case filters
        case detail
        case detailBottom = "detail-bottom"
        case account
    }

    let screen: Screen
    /// Gregorian weekday (1 = Sunday … 7 = Saturday); nil keeps today.
    let weekday: Int?
    /// Turns off "Runs only" and other filters before the screenshot.
    let showEverything: Bool

    static let current: ScreenshotScene? = {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "FRCScreenshotScene"),
              let screen = Screen(rawValue: raw)
        else { return nil }
        let weekday = defaults.integer(forKey: "FRCScreenshotWeekday")
        return ScreenshotScene(
            screen: screen,
            weekday: (1...7).contains(weekday) ? weekday : nil,
            showEverything: defaults.bool(forKey: "FRCScreenshotShowEverything")
        )
    }()
}
#endif
