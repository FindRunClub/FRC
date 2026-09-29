import FRCKit
import SwiftUI

/// The main screen: a day-of-week strip over a map (or list) of that day's runs.
struct EventsHomeView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case map = "Map"
        case list = "List"

        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @State private var displayMode: DisplayMode = .map
    @State private var selectedOccurrence: EventOccurrence?
    @State private var isShowingAccount = false

    var body: some View {
        let store = model.events

        NavigationStack {
            VStack(spacing: 0) {
                DayStripView(
                    days: store.schedule.days,
                    selectedDay: Binding(get: { store.selectedDay }, set: { store.selectedDay = $0 }),
                    eventCount: { store.occurrences(on: $0).count }
                )

                if model.isUsingDemoData {
                    DemoDataBanner(
                        message: model.auth.lastError,
                        canConnect: model.auth.state != .notConfigured && !model.auth.isSignedIn,
                        openAccount: { isShowingAccount = true }
                    )
                }

                Divider()

                ZStack(alignment: .bottom) {
                    switch displayMode {
                    case .map:
                        EventsMapView(
                            clusters: store.selectedClusters,
                            selectedDay: store.selectedDay,
                            onSelect: { selectedOccurrence = $0 }
                        )
                    case .list:
                        EventsListView(
                            day: store.selectedDay,
                            occurrences: store.selectedOccurrences,
                            failures: store.failures,
                            onSelect: { selectedOccurrence = $0 },
                            onRefresh: { await store.load() }
                        )
                    }

                    statusOverlay(store: store)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingAccount = true
                    } label: {
                        Image(systemName: model.auth.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    FilterMenu(store: store)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedOccurrence) { occurrence in
                EventDetailView(occurrence: occurrence, dataSource: store.dataSource)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingAccount) {
                AccountView()
            }
        }
    }

    @ViewBuilder
    private func statusOverlay(store: EventsStore) -> some View {
        switch store.phase {
        case .idle, .loading:
            if store.schedule.allOccurrences.isEmpty {
                StatusCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(store.isDemo ? "Loading demo clubs…" : "Loading your clubs' events…")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        case .failed(let message):
            StatusCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Couldn't load events", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await store.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .loaded:
            if store.clubs.isEmpty {
                StatusCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No clubs yet").font(.headline)
                        Text("Join run clubs on Strava and their events will show up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if store.selectedOccurrences.isEmpty {
                EmptyDayCard(
                    day: store.selectedDay,
                    hiddenCount: store.hiddenCountForSelectedDay,
                    showEverything: { store.showEverything() }
                )
            } else if displayMode == .map, store.unmappableCountForSelectedDay > 0 {
                StatusCard {
                    Button {
                        displayMode = .list
                    } label: {
                        Label(
                            "\(store.unmappableCountForSelectedDay) without a map location. See the list.",
                            systemImage: "list.bullet"
                        )
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }
}

/// Filters: runs only, and which clubs to show.
private struct FilterMenu: View {
    let store: EventsStore

    var body: some View {
        Menu {
            Toggle("Runs only", isOn: Binding(
                get: { store.eventFilter.runsOnly },
                set: { store.setRunsOnly($0) }
            ))
            if !store.clubs.isEmpty {
                Section("Clubs") {
                    ForEach(store.clubs) { club in
                        Toggle(club.name, isOn: Binding(
                            get: { store.isClubVisible(club.id) },
                            set: { store.setClub(club.id, visible: $0) }
                        ))
                    }
                }
            }
            Section {
                Button("Show Everything") { store.showEverything() }
                Button {
                    Task { await store.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            Image(systemName: store.eventFilter.hiddenClubIDs.isEmpty
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filters")
    }
}

private struct DemoDataBanner: View {
    let message: String?
    let canConnect: Bool
    let openAccount: () -> Void

    var body: some View {
        Button(action: openAccount) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Showing demo clubs in New York City")
                        .font(.footnote.weight(.semibold))
                    if let message {
                        Text(message)
                            .font(.caption)
                    } else if canConnect {
                        Text("Connect Strava to see your clubs' events.")
                            .font(.caption)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.stravaOrange)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stravaOrange.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyDayCard: View {
    let day: LocalDay
    let hiddenCount: Int
    let showEverything: () -> Void

    var body: some View {
        StatusCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("No runs on \(day.weekdayName)")
                    .font(.headline)
                if hiddenCount > 0 {
                    Text("\(hiddenCount) other \(hiddenCount == 1 ? "event is" : "events are") hidden by your filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Show Everything", action: showEverything)
                        .buttonStyle(.bordered)
                } else {
                    Text("Pick another day above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StatusCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}
