import Foundation

/// Club events laid out over the next N days, starting today.
public struct WeekSchedule: Sendable {
    public let days: [LocalDay]
    private let occurrencesByDay: [LocalDay: [EventOccurrence]]

    /// - Parameters:
    ///   - now: The reference time; "today" is computed in `timeZone`.
    ///   - dayCount: How many days the strip covers.
    ///   - pastGrace: Occurrences that started less than this long ago still show.
    public init(
        events: [ClubEvent],
        now: Date,
        timeZone: TimeZone = .current,
        dayCount: Int = 7,
        pastGrace: TimeInterval = 60 * 60
    ) {
        let today = LocalDay(now, timeZone: timeZone)
        let days = (0..<max(dayCount, 1)).map { today.adding(days: $0) }
        let visibleDays = Set(days)
        let earliestStart = now.addingTimeInterval(-pastGrace)

        var byDay: [LocalDay: [EventOccurrence]] = [:]
        var seen = Set<String>()
        for clubEvent in events {
            for start in clubEvent.event.upcomingOccurrences where start >= earliestStart {
                let occurrence = EventOccurrence(event: clubEvent.event, club: clubEvent.club, start: start)
                guard visibleDays.contains(occurrence.day), seen.insert(occurrence.id).inserted else { continue }
                byDay[occurrence.day, default: []].append(occurrence)
            }
        }
        for day in byDay.keys {
            byDay[day]?.sort(by: EventOccurrence.chronological)
        }

        self.days = days
        self.occurrencesByDay = byDay
    }

    public static let empty = WeekSchedule(events: [], now: Date())

    public func occurrences(on day: LocalDay) -> [EventOccurrence] {
        occurrencesByDay[day] ?? []
    }

    public var allOccurrences: [EventOccurrence] {
        days.flatMap { occurrences(on: $0) }
    }
}

/// What the user has chosen to see.
public struct EventFilter: Hashable, Sendable, Codable {
    public var runsOnly: Bool
    public var hiddenClubIDs: Set<Int>

    public init(runsOnly: Bool = true, hiddenClubIDs: Set<Int> = []) {
        self.runsOnly = runsOnly
        self.hiddenClubIDs = hiddenClubIDs
    }

    public func includes(_ occurrence: EventOccurrence) -> Bool {
        if runsOnly && !occurrence.event.isRun { return false }
        return !hiddenClubIDs.contains(occurrence.club.id)
    }

    public var isNarrowing: Bool {
        runsOnly || !hiddenClubIDs.isEmpty
    }
}

/// Occurrences that share a start location on the map, so pins don't stack
/// on top of each other when two runs leave from the same spot.
public struct LocationCluster: Identifiable, Hashable, Sendable {
    public let id: String
    public let coordinate: Coordinate
    public let occurrences: [EventOccurrence]

    /// Groups occurrences whose start points round to the same ~11 m cell.
    /// Occurrences without coordinates are skipped (they still appear in the list).
    public static func clusters(for occurrences: [EventOccurrence]) -> [LocationCluster] {
        var order: [String] = []
        var groups: [String: [EventOccurrence]] = [:]
        for occurrence in occurrences {
            guard let coordinate = occurrence.event.startCoordinate else { continue }
            let key = "\(Int((coordinate.latitude * 1e4).rounded())),\(Int((coordinate.longitude * 1e4).rounded()))"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(occurrence)
        }
        return order.compactMap { key in
            guard let group = groups[key]?.sorted(by: EventOccurrence.chronological),
                  let coordinate = group.first?.event.startCoordinate
            else { return nil }
            return LocationCluster(id: key, coordinate: coordinate, occurrences: group)
        }
    }
}
