import FRCKit
import Foundation
import Observation

enum Loadable<Value> {
    case loading
    case loaded(Value)
    case unavailable(String)
}

/// Loads what costs extra API calls (club admins, who's going, full route
/// details) only when a club page opens, each part independently.
@MainActor
@Observable
final class ClubDetailModel {
    let run: ClubRun
    /// Index into `run.options` (the 5 mi / 3 mi route switch).
    var selectedOption = 0
    private(set) var admins: Loadable<[StravaAthlete]> = .loading
    private(set) var attendees: [StravaID: Loadable<[StravaAthlete]>] = [:]
    private(set) var detailedRoutes: [StravaID: StravaRoute] = [:]

    private let dataSource: ClubEventsDataSource
    @ObservationIgnored private var hasLoaded = false

    init(run: ClubRun, dataSource: ClubEventsDataSource) {
        self.run = run
        self.dataSource = dataSource
    }

    var option: EventOccurrence {
        run.options[min(selectedOption, run.options.count - 1)]
    }

    /// The selected option's route: the embedded line, upgraded with
    /// distance and elevation once the full route has loaded.
    var route: StravaRoute? {
        guard let summary = option.event.route else { return nil }
        guard let id = summary.id, let details = detailedRoutes[id] else { return summary }
        return details.merged(with: summary)
    }

    var going: Loadable<[StravaAthlete]> {
        attendees[option.event.id] ?? .loading
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadAdmins() }
            for option in run.options {
                group.addTask { await self.loadAttendees(for: option.event) }
                if let routeID = option.event.route?.id {
                    group.addTask { await self.loadRoute(id: routeID) }
                }
            }
        }
    }

    private func loadAdmins() async {
        do {
            admins = .loaded(try await dataSource.clubAdmins(clubID: run.club.id))
        } catch {
            admins = .unavailable(Self.message(for: error, subject: "Club admins"))
        }
    }

    private func loadAttendees(for event: StravaGroupEvent) async {
        do {
            attendees[event.id] = .loaded(try await dataSource.attendees(eventID: event.id))
        } catch {
            attendees[event.id] = .unavailable(Self.message(for: error, subject: "The attendee list"))
        }
    }

    private func loadRoute(id: StravaID) async {
        // A private route may be off-limits; the embedded line still draws.
        if let details = try? await dataSource.routeDetails(id: id) {
            detailedRoutes[id] = details
        }
    }

    private static func message(for error: Error, subject: String) -> String {
        switch error as? StravaAPIError {
        case .notFound, .forbidden:
            return "\(subject) isn't shared by Strava for this event."
        case .some(let apiError):
            return apiError.localizedDescription
        case .none:
            return error.localizedDescription
        }
    }
}
