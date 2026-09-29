import FRCKit
import SwiftUI

/// Seven day chips (today + the next six), each with its event count.
struct DayStripView: View {
    let days: [LocalDay]
    @Binding var selectedDay: LocalDay
    let eventCount: (LocalDay) -> Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                DayChip(
                    title: index == 0 ? "Today" : day.shortWeekdayName,
                    dayNumber: day.day,
                    count: eventCount(day),
                    isSelected: day == selectedDay
                ) {
                    withAnimation(.snappy) { selectedDay = day }
                }
                .accessibilityLabel("\(index == 0 ? "Today, " : "")\(day.longName), \(eventCount(day)) events")
                .accessibilityAddTraits(day == selectedDay ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct DayChip: View {
    let title: String
    let dayNumber: Int
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(dayNumber)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(count == 0 ? "–" : "\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background {
                        if count > 0 {
                            Capsule().fill(isSelected ? Color.white.opacity(0.25) : Theme.stravaOrange.opacity(0.15))
                        }
                    }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.stravaOrange : Theme.cardBackground)
            )
        }
        .buttonStyle(.plain)
    }
}
