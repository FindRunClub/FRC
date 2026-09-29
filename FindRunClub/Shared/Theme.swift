import CoreLocation
import FRCKit
import SwiftUI

enum Theme {
    /// Strava's brand orange (#FC5200).
    static let stravaOrange = Color(red: 252 / 255, green: 82 / 255, blue: 0 / 255)
    /// Pins for non-run events (shown when "Runs only" is off).
    static let otherActivity = Color.indigo
    static let joined = Color.green
    static let cardBackground = Color(.secondarySystemBackground)
}

extension Coordinate {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A round photo with an initials fallback, for athletes and clubs.
struct AvatarView: View {
    let url: URL?
    let initials: String
    var size: CGFloat = 36

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Theme.stravaOrange.opacity(0.15))
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.stravaOrange)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

extension AvatarView {
    init(athlete: StravaAthlete, size: CGFloat = 36) {
        self.init(url: athlete.profileImageURL, initials: athlete.initials, size: size)
    }

    init(club: StravaClub, size: CGFloat = 36) {
        let words = club.name.split(separator: " ").prefix(2)
        let initials = String(words.compactMap(\.first)).uppercased()
        self.init(url: club.profileImageURL, initials: initials.isEmpty ? "?" : initials, size: size)
    }
}

/// A small rounded label such as "Women only" or "You're going".
struct TagView: View {
    let text: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct EventTag: Hashable {
    let text: String
    let systemImage: String
    let color: Color
}

extension EventOccurrence {
    /// Tags worth showing next to an event in lists and details.
    var tags: [EventTag] {
        var tags: [EventTag] = []
        if event.joined {
            tags.append(EventTag(text: "You're going", systemImage: "checkmark.circle.fill", color: Theme.joined))
        }
        if !event.isRun {
            tags.append(EventTag(text: event.activityLabel, systemImage: "bicycle", color: Theme.otherActivity))
        }
        if event.womenOnly {
            tags.append(EventTag(text: "Women only", systemImage: "figure.run", color: .pink))
        }
        if event.startCoordinate == nil {
            tags.append(EventTag(text: "No map location", systemImage: "mappin.slash", color: .secondary))
        }
        return tags
    }
}
