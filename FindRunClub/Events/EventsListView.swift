import FRCKit
import SwiftUI

/// The selected day's runs in time order: which clubs are running, and when.
struct EventsListView: View {
    let day: LocalDay
    let occurrences: [EventOccurrence]
    let failures: [ClubLoadFailure]
    let onSelect: (EventOccurrence) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            if !occurrences.isEmpty {
                Section {
                    ForEach(occurrences) { occurrence in
                        Button {
                            onSelect(occurrence)
                        } label: {
                            EventRow(occurrence: occurrence)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("\(day.longName) · \(occurrences.count) \(occurrences.count == 1 ? "event" : "events")")
                }
            }

            if !failures.isEmpty {
                Section {
                    ForEach(failures, id: \.club.id) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.club.name).font(.subheadline.weight(.semibold))
                            Text(failure.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Couldn't load some clubs")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await onRefresh() }
    }
}

struct EventRow: View {
    let occurrence: EventOccurrence

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(club: occurrence.club, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(occurrence.timeText)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(occurrence.event.isRun ? Theme.stravaOrange : Theme.otherActivity)
                    if let note = occurrence.timeZoneNote() {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(occurrence.event.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(occurrence.club.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let address = occurrence.event.address {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
