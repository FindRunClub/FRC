import FRCKit
import SwiftUI

/// The Filters wireframe: days (multi-select), time of day, start-time
/// window, distance, plus runs-only and per-club toggles. Changes apply when
/// the athlete taps "Show N clubs"; the close button discards them.
struct FiltersView: View {
    let store: EventsStore
    @State private var draft: RunFilter
    @Environment(\.dismiss) private var dismiss

    init(store: EventsStore) {
        self.store = store
        _draft = State(initialValue: store.filter)
    }

    var body: some View {
        let matchCount = store.runs(matching: draft, search: store.searchText).count
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    daySection
                    timeOfDaySection
                    startWindowSection
                    distanceSection
                    moreSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            footer(count: matchCount)
        }
        .background(Theme.ground)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        HStack {
            IconButton(systemImage: "xmark", label: "Close filters") { dismiss() }
            Spacer()
            Text("Filters")
                .font(FRCFont.display(20))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Reset") {
                withAnimation(.snappy) { draft = RunFilter(days: draft.days) }
            }
            .font(FRCFont.body(15, .semibold))
            .underline()
            .foregroundStyle(Theme.ink)
            .frame(minWidth: Theme.touchTarget, minHeight: Theme.touchTarget)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var daySection: some View {
        FilterSection(title: "Day", note: "Pick one or more") {
            HStack(spacing: 5) {
                ForEach(Weekday.allCases) { weekday in
                    let isOn = draft.days.contains(weekday)
                    Button {
                        if isOn { draft.days.remove(weekday) } else { draft.days.insert(weekday) }
                    } label: {
                        ChipLabel(title: weekday.shortName, isSelected: isOn, height: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weekday.name)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private var timeOfDaySection: some View {
        FilterSection(title: "Time of day") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(TimeSlot.allCases) { slot in
                    let isOn = draft.timeSlot == slot
                    Button {
                        draft.timeSlot = slot
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(slot.longTitle)
                                .font(FRCFont.body(15, .semibold))
                            Text(slot.rangeLabel)
                                .font(FRCFont.mono(12))
                                .opacity(0.8)
                        }
                        .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .background(isOn ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                                .strokeBorder(isOn ? Theme.ink : Theme.line, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private var startWindowSection: some View {
        FilterSection(title: "Start time window") {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    TimeSlider(title: "Earliest", minutes: $draft.earliestMinute)
                    TimeSlider(title: "Latest", minutes: $draft.latestMinute)
                }
            }
        }
    }

    private var distanceSection: some View {
        FilterSection(title: "Distance") {
            FlowLayout(spacing: 8) {
                ForEach(DistanceBucket.allCases) { bucket in
                    let isOn = draft.distance == bucket
                    Button {
                        draft.distance = bucket
                    } label: {
                        ChipLabel(title: bucket.title, isSelected: isOn, capsule: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private var moreSection: some View {
        FilterSection(title: "Activities and clubs") {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    Toggle(isOn: $draft.runsOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Runs only").font(FRCFont.body(15, .semibold))
                            Text("Hide rides and other club activities").font(FRCFont.body(12)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(14)

                    ForEach(store.clubs) { club in
                        Divider().overlay(Theme.line)
                        Toggle(isOn: Binding(
                            get: { !draft.hiddenClubIDs.contains(club.id) },
                            set: { isVisible in
                                if isVisible { draft.hiddenClubIDs.remove(club.id) } else { draft.hiddenClubIDs.insert(club.id) }
                            }
                        )) {
                            Text(club.name).font(FRCFont.body(15))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
            }
        }
    }

    private func footer(count: Int) -> some View {
        Button {
            store.apply(draft)
            dismiss()
        } label: {
            Text("Show \(count) \(count == 1 ? "club" : "clubs")")
        }
        .buttonStyle(FRCButtonStyle(kind: .primary, height: 54))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Theme.ground.overlay(alignment: .top) { Divider().overlay(Theme.line) })
    }
}

private struct FilterSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(FRCFont.body(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let note {
                    Text(note)
                        .font(FRCFont.body(13))
                        .foregroundStyle(Theme.muted)
                }
            }
            content
        }
    }
}

/// "Earliest · 5:00 AM" with a half-hour slider.
private struct TimeSlider: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("\(title) ·")
                    .foregroundStyle(Theme.muted)
                Text(Self.label(for: minutes))
                    .font(FRCFont.mono(13))
                    .foregroundStyle(Theme.ink)
            }
            .font(FRCFont.body(13))
            Slider(
                value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }),
                in: 0...1440,
                step: 30
            )
            .tint(Theme.ink)
            .accessibilityLabel(title)
            .accessibilityValue(Self.label(for: minutes))
        }
    }

    static func label(for minutes: Int) -> String {
        if minutes >= 1440 { return "Midnight" }
        let hour = minutes / 60
        let minute = minutes % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", hour12, minute, hour < 12 ? "AM" : "PM")
    }
}
