import FRCKit
import SwiftUI

/// The runner home screen from the MapView wireframe: search and filters on
/// top, Mon–Sun chips, a time-of-day segment, the map, and a sheet of clubs.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @State private var path: [ClubRun] = []
    @State private var isShowingFilters = false
    @State private var isShowingAccount = false
    @State private var isSheetExpanded = false
    #if DEBUG
    @State private var didApplyScreenshotScene = false
    #endif

    /// Controls stack: 44 + 10 + 44 + 10 + 44, plus padding.
    private let controlsHeight: CGFloat = 168
    private let collapsedSheetHeight: CGFloat = 300

    var body: some View {
        let store = model.events
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                let safeTop = proxy.safeAreaInsets.top
                let safeBottom = proxy.safeAreaInsets.bottom
                let sheetHeight = isSheetExpanded ? max(proxy.size.height * 0.62, collapsedSheetHeight) : collapsedSheetHeight
                let runs = store.visibleRuns
                let selectedID = store.selectedRun?.id

                ZStack(alignment: .top) {
                    EventsMapView(
                        clusters: LocationCluster.clusters(for: runs),
                        selectedRunID: selectedID,
                        framingKey: runs.map(\.id).joined(separator: "|"),
                        topInset: safeTop + controlsHeight,
                        bottomInset: collapsedSheetHeight + safeBottom,
                        onTapRun: { run in
                            if run.id == selectedID {
                                path.append(run)
                            } else {
                                withAnimation(.snappy) { store.selectedRunID = run.id }
                            }
                        }
                    )
                    .ignoresSafeArea()

                    MapControls(
                        store: store,
                        onAccount: { isShowingAccount = true },
                        onFilters: { isShowingFilters = true }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RunsSheet(
                            store: store,
                            runs: runs,
                            selectedRunID: selectedID,
                            height: sheetHeight + safeBottom,
                            bottomPadding: safeBottom,
                            isExpanded: $isSheetExpanded,
                            onOpen: { path.append($0) },
                            onShowAccount: { isShowingAccount = true }
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .background(Theme.ground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ClubRun.self) { run in
                ClubDetailView(run: run, dataSource: store.dataSource)
            }
            .sheet(isPresented: $isShowingFilters) {
                FiltersView(store: store)
            }
            .sheet(isPresented: $isShowingAccount) {
                AccountView()
            }
            #if DEBUG
            .onChange(of: store.phase) {
                applyScreenshotScene(store)
            }
            #endif
        }
    }

    #if DEBUG
    /// Opens the screen requested by CI's screenshot script, once data has loaded.
    private func applyScreenshotScene(_ store: EventsStore) {
        guard let scene = ScreenshotScene.current, store.phase == .loaded, !didApplyScreenshotScene else { return }
        didApplyScreenshotScene = true
        if let weekday = scene.weekday.flatMap(Weekday.init(rawValue:)) {
            store.selectOnly(weekday)
        }
        if scene.showEverything {
            store.showEverything()
        }
        switch scene.screen {
        case .map:
            break
        case .expanded:
            isSheetExpanded = true
        case .filters:
            isShowingFilters = true
        case .detail, .detailBottom:
            let runs = store.visibleRuns
            if let run = runs.first(where: { $0.options.count > 1 }) ?? runs.first {
                path.append(run)
            }
        case .account:
            isShowingAccount = true
        }
    }
    #endif
}

// MARK: - Top controls

private struct MapControls: View {
    @Bindable var store: EventsStore
    let onAccount: () -> Void
    let onFilters: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onAccount) {
                    StrideMark()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Account and settings")

                SearchField(text: $store.searchText)

                Button(action: onFilters) {
                    IconButtonLabel(systemImage: "slider.horizontal.3")
                        .overlay(alignment: .topTrailing) {
                            if store.filter.isNarrowed {
                                Circle()
                                    .fill(Theme.accent)
                                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                                    .frame(width: 12, height: 12)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.filter.isNarrowed ? "Filters, some applied" : "Filters")
            }

            let today = Weekday(LocalDay(Date(), timeZone: .current))
            HStack(spacing: 5) {
                ForEach(Weekday.allCases) { weekday in
                    Button {
                        withAnimation(.snappy) { store.selectOnly(weekday) }
                    } label: {
                        ChipLabel(title: weekday.shortName, isSelected: store.filter.days.contains(weekday))
                            .overlay(alignment: .bottom) {
                                if weekday == today {
                                    Circle()
                                        .fill(store.filter.days.contains(weekday) ? Theme.accent : Theme.ink)
                                        .frame(width: 4, height: 4)
                                        .padding(.bottom, 5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weekday == today ? "\(weekday.name), today" : weekday.name)
                    .accessibilityAddTraits(store.filter.days.contains(weekday) ? .isSelected : [])
                }
            }

            TimeSegment(selection: store.filter.timeSlot) { slot in
                withAnimation(.snappy) { store.setTimeSlot(slot) }
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            TextField("Neighborhood or club", text: $text)
                .font(FRCFont.body(15))
                .foregroundStyle(Theme.ink)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.mid)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.touchTarget)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Any / Early / Midday / Evening, the selected one filled with the accent.
struct TimeSegment: View {
    let selection: TimeSlot
    let onSelect: (TimeSlot) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TimeSlot.allCases) { slot in
                let isSelected = slot == selection
                Button {
                    onSelect(slot)
                } label: {
                    Text(slot.title)
                        .font(FRCFont.body(13, .semibold))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isSelected ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - Sheet

private struct RunsSheet: View {
    let store: EventsStore
    let runs: [ClubRun]
    let selectedRunID: String?
    let height: CGFloat
    let bottomPadding: CGFloat
    @Binding var isExpanded: Bool
    let onOpen: (ClubRun) -> Void
    let onShowAccount: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Capsule()
                    .fill(Theme.line)
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(runs.count) \(runs.count == 1 ? "club" : "clubs")")
                        .font(FRCFont.display(22))
                        .foregroundStyle(Theme.ink)
                    if store.isDemo {
                        Button(action: onShowAccount) {
                            SampleDataBadge()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Explains the sample data and how to connect Strava")
                    }
                    Spacer(minLength: 8)
                    Text(store.whenLabel)
                        .font(FRCFont.body(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy) { isExpanded.toggle() }
            }
            .gesture(
                DragGesture(minimumDistance: 12).onEnded { value in
                    withAnimation(.snappy) {
                        if value.translation.height < -30 { isExpanded = true }
                        if value.translation.height > 30 { isExpanded = false }
                    }
                }
            )
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(isExpanded ? "Collapses the list" : "Expands the list")

            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, bottomPadding)
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.10), radius: 12, y: -6)
        )
    }

    @ViewBuilder
    private var content: some View {
        if runs.isEmpty {
            VStack(spacing: 12) {
                switch store.phase {
                case .idle, .loading:
                    ProgressView()
                    Text(store.isDemo ? "Loading sample clubs…" : "Loading your clubs' events…")
                case .failed(let message):
                    Text("Couldn't load club events").font(FRCFont.body(15, .semibold)).foregroundStyle(Theme.ink)
                    Text(message)
                    Button("Try again") {
                        Task { await store.load() }
                    }
                    .buttonStyle(FRCButtonStyle(kind: .primary, height: 44))
                case .loaded:
                    Text(store.clubs.isEmpty
                        ? "Join run clubs on Strava and their events show up here."
                        : "No clubs match. Try another day or time.")
                    if store.filter.isNarrowed || !store.searchText.isEmpty {
                        Button("Clear filters") {
                            withAnimation(.snappy) {
                                store.searchText = ""
                                store.apply(RunFilter(days: store.filter.days))
                            }
                        }
                        .buttonStyle(FRCButtonStyle(kind: .secondary, height: 44))
                    }
                }
            }
            .font(FRCFont.body(14))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(runs) { run in
                            Button {
                                onOpen(run)
                            } label: {
                                RunCard(run: run, isSelected: run.id == selectedRunID, showsDay: store.filter.days.count != 1)
                            }
                            .buttonStyle(.plain)
                            .id(run.id)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedRunID) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }
}

/// A club row: start time, name, neighborhood and distance, average turnout.
struct RunCard: View {
    let run: ClubRun
    let isSelected: Bool
    var showsDay = false

    var body: some View {
        let parts = run.timeParts
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                if showsDay {
                    Text(run.weekday.shortName)
                        .font(FRCFont.body(10, .semibold))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                }
                Text(parts.time)
                    .font(FRCFont.mono(15, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(parts.period)
                    .font(FRCFont.body(11))
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: 52)
            .padding(.vertical, 6)
            .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(run.club.name)
                        .font(FRCFont.body(15, .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if run.options.contains(where: { $0.event.joined }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .accessibilityLabel("You're going")
                    }
                }
                Text([run.place.area, run.distanceLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(FRCFont.body(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(run.turnout?.average.map { String($0) } ?? "–")
                    .font(FRCFont.mono(14, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("avg runners")
                    .font(FRCFont.body(11))
                    .foregroundStyle(Theme.muted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(isSelected ? Theme.ink : Theme.line, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the club page")
    }
}

extension RunFilter {
    /// True when anything beyond the day chips narrows the results.
    var isNarrowed: Bool {
        timeSlot != .any || hasStartWindow || distance != .any || !hiddenClubIDs.isEmpty
    }
}
