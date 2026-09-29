import FRCKit
import MapKit
import SwiftUI

/// The ClubDetail wireframe (route map, route switch, stats, 8-week turnout,
/// directions and Strava), plus the host, club admins and who's going.
struct ClubDetailView: View {
    @State private var model: ClubDetailModel
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isChoosingDirections = false
    #if DEBUG
    @State private var didApplyScreenshotScene = false
    #endif

    init(run: ClubRun, dataSource: ClubEventsDataSource) {
        _model = State(initialValue: ClubDetailModel(run: run, dataSource: dataSource))
    }

    private var run: ClubRun { model.run }
    private var event: StravaGroupEvent { model.option.event }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        routeHeader(topInset: geometry.safeAreaInsets.top)
                        VStack(alignment: .leading, spacing: 16) {
                            titleBlock
                            stats
                            turnoutCard
                            peopleCard
                            aboutCard
                            actions
                                .id("actions")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .top) {
                    // Keeps the status bar readable over the map and scrolled content.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: geometry.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
                .background(Theme.ground)
                .toolbar(.hidden, for: .navigationBar)
                .task { await model.load() }
                #if DEBUG
                .task {
                    guard !didApplyScreenshotScene, ScreenshotScene.current?.screen == .detailBottom else { return }
                    didApplyScreenshotScene = true
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    proxy.scrollTo("actions", anchor: .bottom)
                }
                #endif
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        .confirmationDialog("Get directions", isPresented: $isChoosingDirections, titleVisibility: .visible) {
            if let coordinate = run.coordinate {
                Button("Google Maps") { openURL(Self.googleMapsURL(to: coordinate)) }
                Button("Apple Maps") { openURL(Self.appleMapsURL(to: coordinate)) }
            }
        }
    }

    // MARK: Route header

    private func routeHeader(topInset: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            RouteMap(coordinates: model.route?.coordinates ?? [], start: run.coordinate)
                .id(model.selectedOption)
                .frame(height: 380 + topInset)

            if run.options.count > 1 {
                HStack(spacing: 4) {
                    ForEach(Array(run.options.enumerated()), id: \.offset) { index, option in
                        let isOn = index == model.selectedOption
                        Button {
                            withAnimation(.snappy) { model.selectedOption = index }
                        } label: {
                            Text(option.event.route?.optionLabel ?? "Option \(index + 1)")
                                .font(FRCFont.body(13, .semibold))
                                .foregroundStyle(isOn ? Theme.ground : Theme.ink)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(isOn ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .padding(.horizontal, 16)
                // Sits above Apple's map attribution, which must stay visible.
                .padding(.bottom, 36)
            }
        }
        .overlay(alignment: .top) {
            HStack {
                IconButton(systemImage: "chevron.left", label: "Back to map", circular: true) { dismiss() }
                Spacer()
                IconButton(
                    systemImage: app.savedClubs.contains(run.club.id) ? "bookmark.fill" : "bookmark",
                    label: app.savedClubs.contains(run.club.id) ? "Saved" : "Save club",
                    circular: true
                ) {
                    app.savedClubs.toggle(run.club.id)
                }
                ShareLink(
                    item: event.stravaURL,
                    subject: Text(run.club.name),
                    message: Text("\(run.club.name) runs \(run.weekday.pluralName) at \(run.timeParts.time) \(run.timeParts.period)")
                ) {
                    IconButtonLabel(systemImage: "square.and.arrow.up", circular: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share club")
            }
            .padding(.horizontal, 16)
            .padding(.top, topInset + 8)
        }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(scheduleTag)
                    .font(FRCFont.body(12, .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
                Text("\(run.timeParts.time) \(run.timeParts.period)")
                    .font(FRCFont.mono(13))
                    .foregroundStyle(Theme.ink)
                if let note = run.primary.timeZoneNote() {
                    Text(note).font(FRCFont.mono(12)).foregroundStyle(Theme.muted)
                }
            }
            Text(run.club.name)
                .font(FRCFont.display(28, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if event.title != run.club.name {
                Text(event.title)
                    .font(FRCFont.body(15, .medium))
                    .foregroundStyle(Theme.ink)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(run.place.meetingPoint.map { "Meets at \($0)" } ?? "Meeting point not listed")
            }
            .font(FRCFont.body(14))
            .foregroundStyle(Theme.muted)
            if run.options.contains(where: { $0.event.joined }) {
                Label("You're going", systemImage: "checkmark.circle.fill")
                    .font(FRCFont.body(13, .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    /// "Weekly · Tuesdays" when Strava says it repeats, otherwise the date.
    private var scheduleTag: String {
        if event.frequency == "weekly" {
            return "Weekly · \(run.weekday.pluralName)"
        }
        return run.start.formatted(Date.FormatStyle(timeZone: run.timeZone).weekday(.wide).month(.abbreviated).day())
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: 8) {
            StatTile(label: "Distance", value: model.route?.estimatedDistance.map { RunFormatting.miles($0) } ?? "–")
            StatTile(label: "Elevation", value: model.route?.elevationGain.map { "+\(RunFormatting.feet($0))" } ?? "–")
            if let average = run.turnout?.average {
                StatTile(label: "Avg runners", value: "\(average)")
            } else if case .loaded(let athletes) = model.going {
                StatTile(label: "Going", value: "\(athletes.count)")
            } else {
                StatTile(label: "Avg runners", value: "–")
            }
        }
    }

    // MARK: Turnout

    private var turnoutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Turnout, last 8 weeks").font(FRCFont.body(13, .semibold))
                    Spacer()
                    Text("From club events").font(FRCFont.body(13)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)

                if let turnout = run.turnout, !turnout.weekly.isEmpty {
                    TurnoutBars(weekly: Array(turnout.weekly.suffix(8)))
                    HStack {
                        Text("\(min(turnout.weekly.count, 8)) wks ago")
                        Spacer()
                        if let growth = turnout.growthPercent {
                            Text("\(growth >= 0 ? "+" : "−")\(abs(growth))% · peak \(turnout.peak ?? 0)")
                                .font(FRCFont.mono(11))
                        }
                        Spacer()
                        Text("This week")
                    }
                    .font(FRCFont.body(11))
                    .foregroundStyle(Theme.muted)
                } else {
                    Text("Strava doesn't share past attendance, so this chart fills in as FRC tracks the club week to week.")
                        .font(FRCFont.body(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: People

    private var peopleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("People")
                if let host = event.organizingAthlete {
                    PersonRow(athlete: host, role: "Host")
                }

                Divider().overlay(Theme.line)

                switch model.going {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Counting who's going…").foregroundStyle(Theme.muted)
                    }
                    .font(FRCFont.body(14))
                case .loaded(let athletes):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(athletes.count)").font(FRCFont.mono(20, .semibold))
                            Text("going this week").font(FRCFont.body(14)).foregroundStyle(Theme.muted)
                        }
                        .foregroundStyle(Theme.ink)
                        if !athletes.isEmpty {
                            AvatarStack(athletes: athletes)
                        }
                    }
                case .unavailable(let message):
                    Text(message).font(FRCFont.body(13)).foregroundStyle(Theme.muted)
                }

                Divider().overlay(Theme.line)

                Text("Club admins").font(FRCFont.body(13, .semibold)).foregroundStyle(Theme.ink)
                switch model.admins {
                case .loading:
                    ProgressView()
                case .loaded(let admins) where admins.isEmpty:
                    Text("No admins listed.").font(FRCFont.body(13)).foregroundStyle(Theme.muted)
                case .loaded(let admins):
                    ForEach(Array(admins.enumerated()), id: \.offset) { _, admin in
                        PersonRow(athlete: admin, role: "Admin")
                    }
                case .unavailable(let message):
                    Text(message).font(FRCFont.body(13)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: About

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("About this run")
                if let description = event.eventDescription {
                    Text(description)
                        .font(FRCFont.body(14))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(facts, id: \.label) { fact in
                    HStack {
                        Text(fact.label).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(fact.value).foregroundStyle(Theme.ink)
                    }
                    .font(FRCFont.body(14))
                }
            }
        }
    }

    private var facts: [(label: String, value: String)] {
        var facts: [(label: String, value: String)] = [("Activity", event.activityLabel)]
        if let pace = event.skillLevelLabel { facts.append(("Pace", pace)) }
        if let terrain = event.terrainLabel { facts.append(("Terrain", terrain)) }
        if event.womenOnly { facts.append(("Who", "Women only")) }
        if event.isPrivate { facts.append(("Visibility", "Club members only")) }
        if let members = run.club.memberCount { facts.append(("Club members", members.formatted())) }
        return facts
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Get directions") { isChoosingDirections = true }
                .buttonStyle(FRCButtonStyle(kind: .primary))
                .disabled(run.coordinate == nil)
            Button("View on Strava") { openURL(event.stravaURL) }
                .buttonStyle(FRCButtonStyle(kind: .secondary))
        }
        .padding(.top, 4)
    }

    private static func googleMapsURL(to coordinate: Coordinate) -> URL {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)")!
    }

    private static func appleMapsURL(to coordinate: Coordinate) -> URL {
        URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)")!
    }
}

// MARK: - Building blocks

private struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(FRCFont.body(15, .semibold))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(FRCFont.body(12))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(FRCFont.mono(19, .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Eight weekly bars; this week in the accent, earlier weeks in the line color.
private struct TurnoutBars: View {
    let weekly: [Int]

    var body: some View {
        let peak = max(weekly.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(weekly.enumerated()), id: \.offset) { index, value in
                UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                    .fill(index == weekly.count - 1 ? Theme.accent : Theme.line)
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                            .stroke(Theme.ink, lineWidth: 1.5)
                    )
                    .frame(height: max(4, 56 * CGFloat(value) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly turnout: \(weekly.map { String($0) }.joined(separator: ", ")) runners")
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
                    .font(FRCFont.body(15, .medium))
                    .foregroundStyle(Theme.ink)
                Text(role)
                    .font(FRCFont.body(12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Overlapping avatars for the first few athletes going.
private struct AvatarStack: View {
    let athletes: [StravaAthlete]
    private let maxShown = 8

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(athletes.prefix(maxShown).enumerated()), id: \.offset) { _, athlete in
                AvatarView(athlete: athlete, size: 32)
                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
            }
            if athletes.count > maxShown {
                Text("+\(athletes.count - maxShown)")
                    .font(FRCFont.mono(12, .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(athletes.count) athletes going")
    }
}

/// Route line with an ink casing and accent core, and a Start marker.
private struct RouteMap: View {
    let coordinates: [Coordinate]
    let start: Coordinate?

    var body: some View {
        let line = coordinates.map(\.locationCoordinate)
        let startPoint = (coordinates.first ?? start)?.locationCoordinate
        Map(initialPosition: initialPosition, interactionModes: [.pan, .zoom]) {
            if line.count > 1 {
                MapPolyline(coordinates: line)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: line)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let startPoint {
                Annotation("Start", coordinate: startPoint, anchor: UnitPoint(x: 0.5, y: 0.2)) {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(Theme.ink)
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 3))
                            .frame(width: 20, height: 20)
                        Text("Start")
                            .font(FRCFont.body(12, .semibold))
                            .foregroundStyle(Theme.ground)
                            .frame(width: 52, height: 24)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .overlay {
            if line.count < 2 {
                Text(start == nil ? "No map location shared" : "No route shared for this run")
                    .font(FRCFont.body(13, .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
        }
    }

    /// Frames the route with room for the buttons on top and the switch below.
    private var initialPosition: MapCameraPosition {
        let points = coordinates.isEmpty ? [start].compactMap { $0 } : coordinates
        guard let bounds = CoordinateBounds(points) else { return .automatic }
        let span = bounds.paddedSpan(padding: 1.9, minimumSpan: 0.012)
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.center.latitude + span.latitudeDelta * 0.04, longitude: bounds.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: span.latitudeDelta, longitudeDelta: span.longitudeDelta)
        ))
    }
}
