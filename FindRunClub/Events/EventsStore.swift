import FRCKit
import Foundation
import Observation

/// Loads club events from the active data source and serves the runs that
/// match the day chips, time segment, Filters screen and search.
@MainActor
@Observable
final class EventsStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var isDemo = true
    private(set) var clubs: [StravaClub] = []
    private(set) var failures: [ClubLoadFailure] = []
    private(set) var schedule: WeekSchedule = .empty
    /// True after Strava rejected the saved session.
    private(set) var needsReconnect = false
    /// Everything but the day selection is remembered between launches;
    /// the days reset to today.
    private(set) var filter: RunFilter
    var searchText = ""
    /// The highlighted run (pin and card); nil falls back to the first match.
    var selectedRunID: String?

    @ObservationIgnored private(set) var dataSource: ClubEventsDataSource = DemoClubEventsDataSource()
    @ObservationIgnored private var events: [ClubEvent] = []
    @ObservationIgnored private var turnout: [StravaID: TurnoutHistory] = [:]
    @ObservationIgnored private var loadGeneration = 0

    private static let filterKey = "runFilter"

    init() {
        var filter = Self.loadFilter()
        filter.days = [Weekday(LocalDay(Date(), timeZone: .current))]
        self.filter = filter
    }

    // MARK: Loading

    func use(_ dataSource: ClubEventsDataSource, isDemo: Bool) {
        self.dataSource = dataSource
        self.isDemo = isDemo
        events = []
        turnout = [:]
        clubs = []
        failures = []
        schedule = .empty
        selectedRunID = nil
        phase = .idle
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        phase = .loading
        needsReconnect = false
        do {
            let snapshot = try await dataSource.loadClubEvents()
            guard generation == loadGeneration else { return }
            events = snapshot.events
            turnout = snapshot.turnout
            clubs = snapshot.clubs
            failures = snapshot.failures
            schedule = WeekSchedule(events: events, now: Date(), timeZone: .current)
            phase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            if Task.isCancelled {
                phase = .idle
                return
            }
            let apiError = error as? StravaAPIError
            needsReconnect = apiError == .unauthorized || apiError == .notSignedIn
            phase = .failed(error.localizedDescription)
        }
    }

    /// Keeps the week anchored on today after midnight or a long background stay.
    func rollOverToTodayIfNeeded(now: Date = Date()) {
        guard schedule.days.first != LocalDay(now, timeZone: .current) else { return }
        schedule = WeekSchedule(events: events, now: now, timeZone: .current)
    }

    // MARK: Reading

    /// Runs matching the current filter and search, soonest first.
    var visibleRuns: [ClubRun] {
        runs(matching: filter, search: searchText)
    }

    var clusters: [LocationCluster] {
        LocationCluster.clusters(for: visibleRuns)
    }

    var selectedRun: ClubRun? {
        let runs = visibleRuns
        return runs.first { $0.id == selectedRunID } ?? runs.first
    }

    /// Live count for the Filters screen's "Show N clubs" button.
    func runs(matching filter: RunFilter, search: String = "") -> [ClubRun] {
        let weekdays = filter.days.isEmpty ? Weekday.allCases : filter.days.sorted()
        return weekdays
            .compactMap { schedule.day(for: $0) }
            .flatMap { ClubRun.group(schedule.occurrences(on: $0), turnout: turnout) }
            .filter { filter.includes($0, search: search) }
            .sorted { $0.start < $1.start }
    }

    /// "Tuesday · Evening"
    var whenLabel: String {
        "\(filter.daysLabel) · \(filter.timeSlot.longTitle)"
    }

    // MARK: Filtering

    /// Day chip on the map: show just that day.
    func selectOnly(_ weekday: Weekday) {
        filter.days = [weekday]
        selectedRunID = nil
    }

    func setTimeSlot(_ slot: TimeSlot) {
        filter.timeSlot = slot
        selectedRunID = nil
        saveFilter()
    }

    /// From the Filters screen.
    func apply(_ newFilter: RunFilter) {
        filter = newFilter
        selectedRunID = nil
        saveFilter()
    }

    func showEverything() {
        apply(RunFilter(days: filter.days, runsOnly: false))
    }

    private func saveFilter() {
        var stored = filter
        stored.days = []
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.filterKey)
        }
    }

    private static func loadFilter() -> RunFilter {
        guard let data = UserDefaults.standard.data(forKey: filterKey),
              let filter = try? JSONDecoder().decode(RunFilter.self, from: data)
        else { return RunFilter() }
        return filter
    }
}

/// Clubs the athlete bookmarked on the club page.
@MainActor
@Observable
final class SavedClubs {
    private(set) var ids: Set<Int>
    private static let key = "savedClubIDs"

    init() {
        ids = Set(UserDefaults.standard.array(forKey: Self.key) as? [Int] ?? [])
    }

    func contains(_ clubID: Int) -> Bool {
        ids.contains(clubID)
    }

    func toggle(_ clubID: Int) {
        if ids.contains(clubID) {
            ids.remove(clubID)
        } else {
            ids.insert(clubID)
        }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }
}
