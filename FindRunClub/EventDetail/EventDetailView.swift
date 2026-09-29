import FRCKit
import MapKit
import SwiftUI

/// Everything about one run: when, where, who's hosting, who's going, and the route.
struct EventDetailView: View {
    @State private var model: EventDetailModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(occurrence: EventOccurrence, dataSource: ClubEventsDataSource) {
        _model = State(initialValue: EventDetailModel(occurrence: occurrence, dataSource: dataSource))
    }

    private var occurrence: EventOccurrence { model.occurrence }
    private var event: StravaGroupEvent { model.occurrence.event }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    routeCard
                    peopleCard
                    locationCard
                    detailsCard
                    stravaFooter
                }
                .padding(16)
            }
            .navigationTitle(occurrence.timeText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.load() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(club: occurrence.club, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(occurrence.club.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Label(occurrence.dateTimeText, systemImage: "clock.fill")
                .font(.headline)
                .foregroundStyle(Theme.stravaOrange)

            if let recurrence = event.recurrenceLabel {
                Label(recurrence, systemImage: "repeat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let tags = occurrence.tags
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.text) { tag in
                        TagView(text: tag.text, systemImage: tag.systemImage, color: tag.color)
                    }
                }
            }
        }
    }

    // MARK: Route

    private var routeCard: some View {
        DetailCard(title: "Route", systemImage: "map") {
            if let route = model.route, route.coordinates.count > 1 {
                RoutePreviewMap(coordinates: route.coordinates.map(\.locationCoordinate))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let name = route.name {
                    Text(name).font(.subheadline.weight(.semibold))
                }

                HStack(spacing: 16) {
                    if let distance = route.distance {
                        Stat(label: "Distance", value: RunFormatting.distance(meters: distance))
                    }
                    if let elevation = route.elevationGain {
                        Stat(label: "Elevation", value: RunFormatting.elevation(meters: elevation))
                    }
                    if let time = route.estimatedMovingTime, time > 0 {
                        Stat(label: "Est. time", value: RunFormatting.duration(seconds: time))
                    }
                    if model.isLoadingRouteDetails {
                        ProgressView()
                    }
                }
            } else if model.isLoadingRouteDetails {
                ProgressView("Loading route…")
            } else if event.route != nil {
                Text("Strava didn't share this route's map.")
                    .foregroundStyle(.secondary)
            } else {
                Text("The host hasn't attached a route.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: People

    private var peopleCard: some View {
        DetailCard(title: "People", systemImage: "person.2.fill") {
            if let host = event.organizingAthlete {
                PersonRow(athlete: host, role: "Host")
            }

            Divider()

            switch model.attendees {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Counting attendees…").foregroundStyle(.secondary)
                }
            case .loaded(let athletes):
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(athletes.count) going")
                        .font(.headline)
                    if !athletes.isEmpty {
                        AvatarStack(athletes: athletes)
                    }
                }
            case .unavailable(let message):
                Label(message, systemImage: "person.fill.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Club admins")
                .font(.subheadline.weight(.semibold))
            switch model.admins {
            case .loading:
                ProgressView()
            case .loaded(let admins) where admins.isEmpty:
                Text("No admins listed.").foregroundStyle(.secondary)
            case .loaded(let admins):
                ForEach(Array(admins.enumerated()), id: \.offset) { _, admin in
                    PersonRow(athlete: admin, role: "Admin")
                }
            case .unavailable(let message):
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Location

    private var locationCard: some View {
        DetailCard(title: "Meeting point", systemImage: "mappin.and.ellipse") {
            Text(event.address ?? "No address given")
                .foregroundStyle(event.address == nil ? Color.secondary : Color.primary)
            if let coordinate = event.startCoordinate {
                Button {
                    openURL(Self.directionsURL(to: coordinate))
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private static func directionsURL(to coordinate: Coordinate) -> URL {
        URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=w")!
    }

    // MARK: Details

    @ViewBuilder
    private var detailsCard: some View {
        let facts = detailFacts
        if !facts.isEmpty || event.eventDescription != nil {
            DetailCard(title: "Details", systemImage: "info.circle.fill") {
                ForEach(facts, id: \.label) { fact in
                    LabeledContent(fact.label, value: fact.value)
                }
                if let description = event.eventDescription {
                    Text(description)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var detailFacts: [(label: String, value: String)] {
        var facts: [(label: String, value: String)] = [("Activity", event.activityLabel)]
        if let skill = event.skillLevelLabel { facts.append(("Pace", skill)) }
        if let terrain = event.terrainLabel { facts.append(("Terrain", terrain)) }
        if event.womenOnly { facts.append(("Who", "Women only")) }
        if event.isPrivate { facts.append(("Visibility", "Club members only")) }
        if let members = occurrence.club.memberCount { facts.append(("Club members", members.formatted())) }
        return facts
    }

    // MARK: Strava

    private var stravaFooter: some View {
        VStack(spacing: 10) {
            Button {
                openURL(event.stravaURL)
            } label: {
                Text("View on Strava")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Powered by Strava")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

// MARK: - Building blocks

private struct DetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }
}

private struct PersonRow: View {
    let athlete: StravaAthlete
    let role: String

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(athlete: athlete, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(athlete.displayName)
                    .font(.body.weight(.medium))
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Overlapping avatars for the first few attendees.
private struct AvatarStack: View {
    let athletes: [StravaAthlete]
    private let maxShown = 8

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(athletes.prefix(maxShown).enumerated()), id: \.offset) { _, athlete in
                AvatarView(athlete: athlete, size: 32)
                    .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 2))
            }
            if athletes.count > maxShown {
                Text("+\(athletes.count - maxShown)")
                    .font(.caption.weight(.bold))
                    .padding(.leading, 16)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(athletes.count) athletes going")
    }
}

/// A small map of the route line with a start marker (pan and zoom only).
private struct RoutePreviewMap: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.stravaOrange, lineWidth: 4)
            if let start = coordinates.first {
                Annotation("Start", coordinate: start, anchor: .center) {
                    Circle()
                        .fill(Theme.joined)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .annotationTitles(.hidden)
    }
}
