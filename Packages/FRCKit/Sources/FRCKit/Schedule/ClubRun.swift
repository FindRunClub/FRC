import Foundation

/// Weekly turnout for a run, oldest week first (what the 8-week chart shows).
///
/// Strava doesn't expose past attendance, so live data has no history until
/// something records the "going" count each week; the demo data includes it.
public struct TurnoutHistory: Hashable, Sendable, Codable {
    public let weekly: [Int]

    public init(weekly: [Int]) {
        self.weekly = weekly
    }

    public var average: Int? {
        guard !weekly.isEmpty else { return nil }
        return Int((Double(weekly.reduce(0, +)) / Double(weekly.count)).rounded())
    }

    public var peak: Int? { weekly.max() }

    public var latest: Int? { weekly.last }

    /// Mean of the last two weeks against the first two, as a percentage.
    public var growthPercent: Int? {
        guard weekly.count >= 4 else { return nil }
        let first = Double(weekly[0] + weekly[1]) / 2
        let last = Double(weekly[weekly.count - 2] + weekly[weekly.count - 1]) / 2
        guard first > 0 else { return nil }
        return Int(((last - first) / first * 100).rounded())
    }
}

/// One club meetup: a club, a start time and a meeting point. Clubs often
/// post one Strava event per distance ("5 mi" and "3 mi" leaving together),
/// so those become route options of a single run.
public struct ClubRun: Identifiable, Hashable, Sendable {
    public let id: String
    public let club: StravaClub
    public let start: Date
    /// Longest route first.
    public let options: [EventOccurrence]
    public let turnout: TurnoutHistory?

    public var primary: EventOccurrence { options[0] }
    public var coordinate: Coordinate? { options.lazy.compactMap(\.event.startCoordinate).first }
    public var timeZone: TimeZone { primary.timeZone }
    public var day: LocalDay { primary.day }
    public var weekday: Weekday { Weekday(day) }

    /// Minutes after local midnight where the run happens.
    public var minuteOfDay: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: start)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Route distances in miles, where known.
    public var routeMiles: [Double] {
        options.compactMap { $0.event.route?.estimatedDistance.map { $0 / 1_609.344 } }
    }

    public var place: PlaceDescription {
        PlaceDescription(address: primary.event.address, fallbackArea: club.city)
    }

    /// "6:00" and "PM" in the run's local time.
    public var timeParts: (time: String, period: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm"
        let time = formatter.string(from: start)
        formatter.dateFormat = "a"
        return (time, formatter.string(from: start))
    }

    /// "5.0 mi" or "3.0 / 5.0 mi"
    public var distanceLabel: String? {
        let miles = routeMiles.sorted()
        guard !miles.isEmpty else { return nil }
        return miles.map { String(format: "%.1f", $0) }.joined(separator: " / ") + " mi"
    }

    public func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack: [String?] = [club.name, place.area, primary.event.address, club.city]
            + options.map { Optional($0.event.title) }
        return haystack.compactMap { $0 }.contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Groups one day's occurrences into runs, sorted by start time.
    public static func group(_ occurrences: [EventOccurrence], turnout: [StravaID: TurnoutHistory] = [:]) -> [ClubRun] {
        var order: [String] = []
        var groups: [String: [EventOccurrence]] = [:]
        for occurrence in occurrences {
            let place = occurrence.event.startCoordinate.map(LocationCluster.key(for:)) ?? "none"
            let key = "\(occurrence.club.id)@\(Int(occurrence.start.timeIntervalSince1970))@\(place)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(occurrence)
        }
        return order.compactMap { key -> ClubRun? in
            guard let members = groups[key], let first = members.first else { return nil }
            let options = members.sorted {
                ($0.event.route?.estimatedDistance ?? 0) > ($1.event.route?.estimatedDistance ?? 0)
            }
            let history = options.lazy.compactMap { turnout[$0.event.id] }.first
            return ClubRun(id: key, club: first.club, start: first.start, options: options, turnout: history)
        }
        .sorted { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.club.name < rhs.club.name
        }
    }
}

/// A meeting point split out of Strava's free-text address, e.g.
/// "Pier 62, Chelsea Piers, New York, NY" -> spot "Pier 62, Chelsea Piers", area "Chelsea Piers".
public struct PlaceDescription: Hashable, Sendable {
    /// Neighborhood or park, for list rows.
    public let area: String?
    /// The address without city/state, for "Meets at …".
    public let meetingPoint: String?

    public init(address: String?, fallbackArea: String? = nil) {
        let parts = (address ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch parts.count {
        case 0:
            area = fallbackArea
            meetingPoint = nil
        case 1, 2, 3:
            area = parts[0]
            meetingPoint = parts[0]
        default:
            area = parts[parts.count - 3]
            meetingPoint = parts.prefix(parts.count - 2).joined(separator: ", ")
        }
    }
}
