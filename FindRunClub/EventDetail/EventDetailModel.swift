import FRCKit
import Foundation
import Observation

/// Loads the parts of an event that cost extra API calls (admins, attendees,
/// full route), only when its details are opened, each section on its own.
@MainActor
@Observable
final class EventDetailModel {
    enum Loadable<Value> {
        case loading
        case loaded(Value)
        case unavailable(String)
    }

    let occurrence: EventOccurrence
    private(set) var admins: Loadable<[StravaAthlete]> = .loading
    private(set) var attendees: Loadable<[StravaAthlete]> = .loading
    /// Starts as the route summary embedded in the event (name + map line),
    /// then gains distance and elevation once the full route loads.
    private(set) var route: StravaRoute?
    private(set) var isLoadingRouteDetails = false

    private let dataSource: ClubEventsDataSource
    @ObservationIgnored private var hasLoaded = false

    init(occurrence: EventOccurrence, dataSource: ClubEventsDataSource) {
        self.occurrence = occurrence
        self.dataSource = dataSource
        self.route = occurrence.event.route
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadAdmins() }
            group.addTask { await self.loadAttendees() }
            group.addTask { await self.loadRouteDetails() }
        }
    }

    private func loadAdmins() async {
        do {
            admins = .loaded(try await dataSource.clubAdmins(clubID: occurrence.club.id))
        } catch {
            admins = .unavailable(Self.message(for: error, subject: "Club admins"))
        }
    }

    private func loadAttendees() async {
        do {
            attendees = .loaded(try await dataSource.attendees(eventID: occurrence.event.id))
        } catch {
            attendees = .unavailable(Self.message(for: error, subject: "The attendee list"))
        }
    }

    private func loadRouteDetails() async {
        guard let routeID = route?.id else { return }
        isLoadingRouteDetails = true
        defer { isLoadingRouteDetails = false }
        // A private route may be off-limits; the embedded map line still shows.
        if let details = try? await dataSource.routeDetails(id: routeID) {
            route = route.map { details.merged(with: $0) } ?? details
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
