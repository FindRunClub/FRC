#if DEBUG
import Foundation

/// Debug-only hooks that let `scripts/capture-screenshots.sh` (run in CI)
/// open a specific screen via launch arguments, e.g.
/// `-FRCScreenshotScene list -FRCScreenshotWeekday 5`.
struct ScreenshotScene {
    enum Screen: String {
        case map
        case list
        case detail
        case detailLarge = "detail-large"
        case account
    }

    let screen: Screen
    /// 1 = Sunday … 7 = Saturday; nil keeps today selected.
    let weekday: Int?
    /// Turns off "Runs only" and club filters before the screenshot.
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
