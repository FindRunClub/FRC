import Foundation

/// An event paired with the club it belongs to.
public struct ClubEvent: Identifiable, Hashable, Sendable {
    public let event: StravaGroupEvent
    public let club: StravaClub

    public init(event: StravaGroupEvent, club: StravaClub) {
        self.event = event
        self.club = club
    }

    public var id: StravaID { event.id }
}

/// One dated instance of a (possibly recurring) event: what shows up as a pin.
public struct EventOccurrence: Identifiable, Hashable, Sendable {
    public let event: StravaGroupEvent
    public let club: StravaClub
    public let start: Date

    public init(event: StravaGroupEvent, club: StravaClub, start: Date) {
        self.event = event
        self.club = club
        self.start = start
    }

    public var id: String { "\(event.id.rawValue)@\(Int(start.timeIntervalSince1970))" }

    /// The event's own time zone, falling back to the device's.
    public var timeZone: TimeZone { event.timeZone ?? .current }

    public var day: LocalDay { LocalDay(start, timeZone: timeZone) }

    /// "6:30 AM", in the event's local time.
    public var timeText: String {
        start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// Time zone abbreviation ("PDT") when the event isn't in the viewer's time zone.
    public func timeZoneNote(viewerTimeZone: TimeZone = .current) -> String? {
        guard timeZone.secondsFromGMT(for: start) != viewerTimeZone.secondsFromGMT(for: start) else { return nil }
        return timeZone.abbreviation(for: start) ?? timeZone.identifier
    }

    /// "Tuesday, Sep 30 · 6:30 AM"
    public var dateTimeText: String {
        let date = start.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.wide).month(.abbreviated).day())
        if let note = timeZoneNote() {
            return "\(date) · \(timeText) \(note)"
        }
        return "\(date) · \(timeText)"
    }

    static func chronological(_ lhs: EventOccurrence, _ rhs: EventOccurrence) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.club.name != rhs.club.name { return lhs.club.name < rhs.club.name }
        return lhs.event.title < rhs.event.title
    }
}
