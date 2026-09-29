import Foundation

/// A calendar date (year/month/day) with no time or time zone attached.
///
/// Events are bucketed by the day they happen *where they happen*, so a
/// Tuesday 9 PM run in Los Angeles stays on Tuesday for a viewer in New York.
public struct LocalDay: Hashable, Comparable, Sendable, Identifiable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, timeZone: TimeZone) {
        let components = Self.calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    public var id: String { description }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func adding(days: Int) -> LocalDay {
        let calendar = Self.calendar(in: Self.utc)
        let shifted = calendar.date(byAdding: .day, value: days, to: noonUTC) ?? noonUTC
        return LocalDay(shifted, timeZone: Self.utc)
    }

    /// 1 = Sunday … 7 = Saturday (Gregorian).
    public var weekday: Int {
        Self.calendar(in: Self.utc).component(.weekday, from: noonUTC)
    }

    /// "Tue"
    public var shortWeekdayName: String {
        noonUTC.formatted(Date.FormatStyle(timeZone: Self.utc).weekday(.abbreviated))
    }

    /// "Tuesday"
    public var weekdayName: String {
        noonUTC.formatted(Date.FormatStyle(timeZone: Self.utc).weekday(.wide))
    }

    /// "Tuesday, Sep 30"
    public var longName: String {
        noonUTC.formatted(Date.FormatStyle(timeZone: Self.utc).weekday(.wide).month(.abbreviated).day())
    }

    /// Noon UTC on this date, a stable instant for formatting the date itself.
    private var noonUTC: Date {
        Self.calendar(in: Self.utc).date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    private static let utc = TimeZone(secondsFromGMT: 0)!

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
