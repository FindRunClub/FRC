import FRCKit
import Foundation
import Observation

/// Loads club events from the active data source and serves them per day,
/// with the user's filters applied.
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
    private(set) var eventFilter: EventFilter
    /// True after Strava rejected the saved session.
    private(set) var needsReconnect = false
    var selectedDay: LocalDay

    @ObservationIgnored private(set) var dataSource: ClubEventsDataSource = DemoClubEventsDataSource()
    @ObservationIgnored private var events: [ClubEvent] = []
    @ObservationIgnored private var loadGeneration = 0

    private static let filterKey = "eventFilter"

    init() {
        selectedDay = LocalDay(Date(), timeZone: .current)
        eventFilter = Self.loadFilter()
    }

    // MARK: Loading

    func use(_ dataSource: ClubEventsDataSource, isDemo: Bool) {
        self.dataSource = dataSource
        self.isDemo = isDemo
        events = []
        clubs = []
        failures = []
        schedule = .empty
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
            clubs = snapshot.clubs
            failures = snapshot.failures
            rebuildSchedule()
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
        rebuildSchedule(now: now)
    }

    private func rebuildSchedule(now: Date = Date()) {
        schedule = WeekSchedule(events: events, now: now, timeZone: .current)
        if !schedule.days.contains(selectedDay), let today = schedule.days.first {
            selectedDay = today
        }
    }

    // MARK: Reading

    var isLoading: Bool { phase == .loading }

    func occurrences(on day: LocalDay) -> [EventOccurrence] {
        let filter = eventFilter
        return schedule.occurrences(on: day).filter { filter.includes($0) }
    }

    var selectedOccurrences: [EventOccurrence] {
        occurrences(on: selectedDay)
    }

    var selectedClusters: [LocationCluster] {
        LocationCluster.clusters(for: selectedOccurrences)
    }

    /// Events on the selected day hidden by the current filters.
    var hiddenCountForSelectedDay: Int {
        schedule.occurrences(on: selectedDay).count - selectedOccurrences.count
    }

    var unmappableCountForSelectedDay: Int {
        selectedOccurrences.filter { $0.event.startCoordinate == nil }.count
    }

    // MARK: Filters

    func setRunsOnly(_ runsOnly: Bool) {
        eventFilter.runsOnly = runsOnly
        saveFilter()
    }

    func isClubVisible(_ clubID: Int) -> Bool {
        !eventFilter.hiddenClubIDs.contains(clubID)
    }

    func setClub(_ clubID: Int, visible: Bool) {
        if visible {
            eventFilter.hiddenClubIDs.remove(clubID)
        } else {
            eventFilter.hiddenClubIDs.insert(clubID)
        }
        saveFilter()
    }

    func showEverything() {
        eventFilter = EventFilter(runsOnly: false, hiddenClubIDs: [])
        saveFilter()
    }

    private func saveFilter() {
        if let data = try? JSONEncoder().encode(eventFilter) {
            UserDefaults.standard.set(data, forKey: Self.filterKey)
        }
    }

    private static func loadFilter() -> EventFilter {
        guard let data = UserDefaults.standard.data(forKey: filterKey),
              let filter = try? JSONDecoder().decode(EventFilter.self, from: data)
        else { return EventFilter() }
        return filter
    }
}
