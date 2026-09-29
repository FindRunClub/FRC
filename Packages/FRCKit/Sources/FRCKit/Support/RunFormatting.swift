import Foundation

/// Distance, elevation and duration strings in the viewer's units
/// (miles/feet in the US and UK, kilometers/meters elsewhere).
public enum RunFormatting {
    public static func distance(meters: Double, locale: Locale = .current) -> String {
        if usesImperialDistance(locale) {
            let miles = meters / 1_609.344
            return "\(miles.formatted(.number.precision(.fractionLength(1)).locale(locale))) mi"
        }
        let kilometers = meters / 1_000
        return "\(kilometers.formatted(.number.precision(.fractionLength(1)).locale(locale))) km"
    }

    public static func elevation(meters: Double, locale: Locale = .current) -> String {
        if locale.measurementSystem == .us {
            let feet = meters * 3.28084
            return "\(Int(feet.rounded()).formatted(.number.locale(locale))) ft"
        }
        return "\(Int(meters.rounded()).formatted(.number.locale(locale))) m"
    }

    /// "1 hr, 5 min" / "45 min"
    public static func duration(seconds: Double) -> String {
        let rounded = max(60, (seconds / 60).rounded() * 60)
        return Duration.seconds(rounded).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// "5.0 mi" (the wireframes use US units throughout).
    public static func miles(_ meters: Double) -> String {
        String(format: "%.1f mi", meters / 1_609.344)
    }

    /// "142 ft"
    public static func feet(_ meters: Double) -> String {
        "\(Int((meters * 3.28084).rounded())) ft"
    }

    private static func usesImperialDistance(_ locale: Locale) -> Bool {
        locale.measurementSystem == .us || locale.measurementSystem == .uk
    }
}
