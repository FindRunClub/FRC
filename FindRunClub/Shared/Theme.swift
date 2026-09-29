import CoreLocation
import FRCKit
import SwiftUI

/// FRC design tokens, "Volt" palette (design handoff `tokens/tokens.json`).
/// Brand rule: never Strava orange or Google Maps colors in UI chrome.
enum Theme {
    static let ink = Color(hex: 0x111315)
    static let ground = Color(hex: 0xF2F2ED)
    static let surface = Color.white
    static let line = Color(hex: 0xDCDCD4)
    static let muted = Color(hex: 0x5C5F66)
    static let mid = Color(hex: 0x8E949C)
    static let accent = Color(hex: 0xC5F135)
    /// Text on top of the accent (ink, since lime is a light accent).
    static let onAccent = ink

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 14
        static let xLarge: CGFloat = 16
        static let sheet: CGFloat = 24
    }

    static let touchTarget: CGFloat = 44
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Archivo for display, Geist for body, Geist Mono for times and stats.
/// Bundled in Resources/Fonts (SIL Open Font License) and listed in Info.plist.
enum FRCFont {
    enum Weight: String {
        case regular = "Regular"
        case medium = "Medium"
        case semibold = "SemiBold"
        case bold = "Bold"
    }

    /// Headings: Archivo ExtraBold at 112% width.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("ArchivoSemiExpanded-ExtraBold", size: size, relativeTo: style)
    }

    /// The "FRC" wordmark: Archivo Black Italic.
    static func logo(_ size: CGFloat) -> Font {
        .custom("Archivo-BlackItalic", fixedSize: size)
    }

    static func body(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Geist-\(weight.rawValue)", size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let available: Weight = weight == .bold ? .semibold : weight
        return .custom("GeistMono-\(available.rawValue)", size: size, relativeTo: style)
    }
}

extension Coordinate {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Logo

/// One slanted bar of the Stride logo, skewed 12° like the italic F.
struct SkewedBar: Shape {
    func path(in rect: CGRect) -> Path {
        let lean = rect.height * tan(12 * .pi / 180)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - lean, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + lean, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The three Stride bars (accent, mid, ground-or-ink), each stepping left so
/// all three sit the same distance from the F.
struct StrideBars: View {
    /// Height of one bar; widths and gaps scale from the 92px wordmark spec.
    var barHeight: CGFloat
    var bottomColor: Color

    var body: some View {
        let gap = barHeight * 0.5
        let step = (barHeight + gap) * tan(12 * .pi / 180)
        VStack(alignment: .trailing, spacing: gap) {
            SkewedBar().fill(Theme.accent).frame(width: barHeight * 5, height: barHeight)
            SkewedBar().fill(Theme.mid).frame(width: barHeight * 3.83, height: barHeight).padding(.trailing, step)
            SkewedBar().fill(bottomColor).frame(width: barHeight * 2.67, height: barHeight).padding(.trailing, step * 2)
        }
        .accessibilityHidden(true)
    }
}

/// The 44pt app mark from the map wireframe: bars + italic F on an ink tile.
struct StrideMark: View {
    var size: CGFloat = 44

    var body: some View {
        let scale = size / 44
        RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
            .fill(Theme.ink)
            .frame(width: size, height: size)
            .overlay {
                HStack(alignment: .center, spacing: 2 * scale) {
                    StrideBars(barHeight: 3.6 * scale, bottomColor: Theme.ground)
                    Text("F")
                        .font(FRCFont.logo(22 * scale))
                        .foregroundStyle(Theme.ground)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("FRC")
    }
}

/// The full "FRC" wordmark with bars.
struct StrideWordmark: View {
    var height: CGFloat = 32
    var onDark = false

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: height * 0.12) {
            StrideBars(barHeight: height * 0.13, bottomColor: onDark ? Theme.ground : Theme.ink)
                .padding(.bottom, height * 0.08)
            Text("FRC")
                .font(FRCFont.logo(height))
                .foregroundStyle(onDark ? Theme.ground : Theme.ink)
        }
        .accessibilityElement()
        .accessibilityLabel("FRC")
    }
}

// MARK: - Components

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
                    Circle().fill(Theme.ground)
                    Text(initials)
                        .font(FRCFont.body(size * 0.36, .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

extension AvatarView {
    init(athlete: StravaAthlete, size: CGFloat = 36) {
        self.init(url: athlete.profileImageURL, initials: athlete.initials, size: size)
    }
}

/// Surface card with the hairline border used throughout the wireframes.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A 44pt square or circular icon button on a surface.
struct IconButton: View {
    let systemImage: String
    let label: String
    var circular = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconButtonLabel(systemImage: systemImage, circular: circular)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct IconButtonLabel: View {
    let systemImage: String
    var circular = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: circular ? Theme.touchTarget / 2 : Theme.Radius.medium, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: Theme.touchTarget, height: Theme.touchTarget)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(shape)
    }
}

/// Full-width primary (ink) and secondary (outlined) buttons.
struct FRCButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, accent }
    var kind: Kind = .primary
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
        configuration.label
            .font(FRCFont.body(15, .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(kind == .primary ? Theme.ground : Theme.ink)
            .background {
                switch kind {
                case .primary: shape.fill(Theme.ink)
                case .accent: shape.fill(Theme.accent)
                case .secondary: shape.fill(Color.clear)
                }
            }
            .overlay {
                if kind != .primary {
                    shape.strokeBorder(Theme.ink, lineWidth: 1.5)
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Selectable chip: ink when selected, surface with a hairline otherwise.
struct ChipLabel: View {
    let title: String
    let isSelected: Bool
    var height: CGFloat = 44
    var capsule = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? height / 2 : Theme.Radius.medium, style: .continuous)
        Text(title)
            .font(FRCFont.body(13, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, capsule ? 16 : 0)
            .frame(maxWidth: capsule ? nil : .infinity)
            .frame(height: height)
            .foregroundStyle(isSelected ? Theme.ground : Theme.ink)
            .background(isSelected ? Theme.ink : Theme.surface, in: shape)
            .overlay(shape.strokeBorder(isSelected ? Theme.ink : Theme.line, lineWidth: 1))
            .contentShape(shape)
    }
}

/// The dashed "Sample data" badge from the Marketer wireframe.
struct SampleDataBadge: View {
    var body: some View {
        Text("Sample data")
            .font(FRCFont.mono(11))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
    }
}

/// Lays out children left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
