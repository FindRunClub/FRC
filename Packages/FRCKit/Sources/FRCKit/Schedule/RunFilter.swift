import Foundation

/// Days of the week, listed Monday first like the day chips.
/// Raw values follow Gregorian `Calendar` numbering (1 = Sunday).
public enum Weekday: Int, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7, sunday = 1

    public var id: Int { rawValue }

    public init(_ day: LocalDay) {
        self = Weekday(rawValue: day.weekday) ?? .monday
    }

    /// "Tue"
    public var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }

    /// "Tuesday"
    public var name: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    /// "Tuesdays"
    public var pluralName: String { name + "s" }

    private var mondayFirstIndex: Int { Weekday.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.mondayFirstIndex < rhs.mondayFirstIndex
    }
}

/// The time-of-day segments from the wireframes. The design's labels were
/// 5–9 AM / 11 AM–2 PM / 5–8 PM; the buckets here are contiguous so a
/// 10 AM or 8:30 PM run isn't hidden from every segment except "Any".
public enum TimeSlot: String, CaseIterable, Codable, Sendable, Identifiable {
    case any
    case early
    case midday
    case evening

    public var id: String { rawValue }

    /// "Early"
    public var title: String {
        switch self {
        case .any: return "Any"
        case .early: return "Early"
        case .midday: return "Midday"
        case .evening: return "Evening"
        }
    }

    /// "Any time" / "Early", for the Filters cards and sheet header.
    public var longTitle: String {
        self == .any ? "Any time" : title
    }

    /// "Before 10 AM"
    public var rangeLabel: String {
        switch self {
        case .any: return "All day"
        case .early: return "Before 10 AM"
        case .midday: return "10 AM–4 PM"
        case .evening: return "4 PM and later"
        }
    }

    /// Minutes after local midnight.
    public var minutes: Range<Int> {
        switch self {
        case .any: return 0..<(24 * 60)
        case .early: return 0..<(10 * 60)
        case .midday: return (10 * 60)..<(16 * 60)
        case .evening: return (16 * 60)..<(24 * 60)
        }
    }

    public func contains(minuteOfDay: Int) -> Bool {
        minutes.contains(minuteOfDay)
    }
}

public enum DistanceBucket: String, CaseIterable, Codable, Sendable, Identifiable {
    case any
    case under3
    case threeToSix
    case sixPlus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: return "Any"
        case .under3: return "Under 3 mi"
        case .threeToSix: return "3–6 mi"
        case .sixPlus: return "6+ mi"
        }
    }

    /// Runs with an unknown distance only match "Any".
    public func contains(miles: Double?) -> Bool {
        guard self != .any else { return true }
        guard let miles else { return false }
        switch self {
        case .any: return true
        case .under3: return miles < 3
        case .threeToSix: return miles >= 3 && miles <= 6
        case .sixPlus: return miles > 6
        }
    }
}

/// Everything the map and Filters screens narrow runs by.
public struct RunFilter: Hashable, Sendable, Codable {
    /// Empty means every day.
    public var days: Set<Weekday>
    public var timeSlot: TimeSlot
    /// Start-time window in minutes after midnight (0...1440 means no limit).
    public var earliestMinute: Int
    public var latestMinute: Int
    public var distance: DistanceBucket
    /// Hide rides and other non-run club events.
    public var runsOnly: Bool
    public var hiddenClubIDs: Set<Int>

    public static let fullDay = 0...(24 * 60)

    public init(
        days: Set<Weekday> = [],
        timeSlot: TimeSlot = .any,
        earliestMinute: Int = 0,
        latestMinute: Int = 24 * 60,
        distance: DistanceBucket = .any,
        runsOnly: Bool = true,
        hiddenClubIDs: Set<Int> = []
    ) {
        self.days = days
        self.timeSlot = timeSlot
        self.earliestMinute = earliestMinute
        self.latestMinute = latestMinute
        self.distance = distance
        self.runsOnly = runsOnly
        self.hiddenClubIDs = hiddenClubIDs
    }

    public var hasStartWindow: Bool {
        earliestMinute > 0 || latestMinute < 24 * 60
    }

    /// Whether a run passes every filter except the day selection (days pick
    /// which dates are loaded) and free-text search.
    public func includes(_ run: ClubRun, search: String = "") -> Bool {
        if runsOnly && !run.options.contains(where: { $0.event.isRun }) { return false }
        if hiddenClubIDs.contains(run.club.id) { return false }
        let minute = run.minuteOfDay
        if !timeSlot.contains(minuteOfDay: minute) { return false }
        let window = min(earliestMinute, latestMinute)...max(earliestMinute, latestMinute)
        if !window.contains(minute) { return false }
        if distance != .any && !run.routeMiles.contains(where: { distance.contains(miles: $0) }) { return false }
        return run.matches(search: search)
    }

    /// "Tuesday" / "Tue, Thu" / "Every day"
    public var daysLabel: String {
        let sorted = days.sorted()
        switch sorted.count {
        case 0, 7: return "Every day"
        case 1: return sorted[0].name
        default: return sorted.map(\.shortName).joined(separator: ", ")
        }
    }
}
