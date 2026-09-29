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

    /// The date in this week that falls on `weekday`.
    public func day(for weekday: Weekday) -> LocalDay? {
        days.first { $0.weekday == weekday.rawValue }
    }

    public var allOccurrences: [EventOccurrence] {
        days.flatMap { occurrences(on: $0) }
    }
}

/// Runs that share a start location on the map, so pins don't stack on
/// top of each other when two clubs leave from the same spot.
public struct LocationCluster: Identifiable, Hashable, Sendable {
    public let id: String
    public let coordinate: Coordinate
    public let runs: [ClubRun]

    /// Groups runs whose start points round to the same ~11 m cell.
    /// Runs without coordinates are skipped (they still appear in the list).
    public static func clusters(for runs: [ClubRun]) -> [LocationCluster] {
        var order: [String] = []
        var groups: [String: [ClubRun]] = [:]
        for run in runs {
            guard let coordinate = run.coordinate else { continue }
            let cell = key(for: coordinate)
            if groups[cell] == nil { order.append(cell) }
            groups[cell, default: []].append(run)
        }
        return order.compactMap { key in
            guard let group = groups[key]?.sorted(by: { $0.start < $1.start }),
                  let coordinate = group.first?.coordinate
            else { return nil }
            return LocationCluster(id: key, coordinate: coordinate, runs: group)
        }
    }

    static func key(for coordinate: Coordinate) -> String {
        "\(Int((coordinate.latitude * 1e4).rounded())),\(Int((coordinate.longitude * 1e4).rounded()))"
    }
}
