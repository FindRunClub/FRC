import CoreLocation
import FRCKit
import MapKit
import SwiftUI

/// The full-bleed map. Each pin is a time button; the selected run turns
/// accent and shows its club name, like the MapView wireframe.
struct EventsMapView: View {
    let clusters: [LocationCluster]
    let selectedRunID: String?
    /// Changes whenever the set of runs changes, to re-frame the camera.
    let framingKey: String
    /// Space covered by the controls above and the sheet below, in points.
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onTapRun: (ClubRun) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var locationPermission = LocationPermission()

    var body: some View {
        GeometryReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                ForEach(clusters) { cluster in
                    Annotation(cluster.accessibilityTitle, coordinate: cluster.coordinate.locationCoordinate, anchor: .bottom) {
                        TimePinStack(runs: cluster.runs, selectedRunID: selectedRunID, onTap: onTapRun)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            // Keep the "you are here" dot Apple-Maps blue so it can't be mistaken for a pin.
            .tint(.blue)
            // Lifts Apple's logo and legal link above the sheet so they stay visible.
            .safeAreaPadding(.bottom, bottomInset)
            .overlay(alignment: .bottomTrailing) {
                IconButton(systemImage: "scope", label: "Center on my location", circular: true) {
                    locationPermission.requestIfNeeded()
                    withAnimation(.easeInOut(duration: 0.45)) {
                        position = .userLocation(fallback: position)
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, bottomInset + 16)
            }
            .onAppear {
                locationPermission.requestIfNeeded()
                frame(in: proxy.size, animated: false)
            }
            .onChange(of: framingKey) {
                frame(in: proxy.size, animated: true)
            }
        }
    }

    /// Fits the pins into the band of map left visible between the controls
    /// and the sheet. Leaves the camera alone when there's nothing to show.
    private func frame(in size: CGSize, animated: Bool) {
        guard let bounds = CoordinateBounds(clusters.map(\.coordinate)), size.height > 0 else { return }
        // Pins stand up from their coordinate, so leave room above the highest one.
        let pinAllowance: CGFloat = 64
        let bandTop = topInset + pinAllowance
        let bandHeight = max(size.height - bandTop - bottomInset, size.height * 0.2)
        let span = bounds.paddedSpan(padding: 1.3, minimumSpan: 0.012)
        let latitudeDelta = span.latitudeDelta * Double(size.height / bandHeight)
        let bandMiddle = bandTop + bandHeight / 2
        let shift = Double((size.height / 2 - bandMiddle) / size.height) * latitudeDelta
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.center.latitude - shift, longitude: bounds.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: span.longitudeDelta)
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }
}

/// Time buttons for every run leaving from one spot.
struct TimePinStack: View {
    let runs: [ClubRun]
    let selectedRunID: String?
    let onTap: (ClubRun) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if let selected = runs.first(where: { $0.id == selectedRunID }) {
                Text(selected.club.name)
                    .font(FRCFont.body(12, .semibold))
                    .foregroundStyle(Theme.ground)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            }
            ForEach(runs) { run in
                Button {
                    onTap(run)
                } label: {
                    TimePill(run: run, isSelected: run.id == selectedRunID)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(run.club.name), \(run.timeParts.time) \(run.timeParts.period)")
                .accessibilityHint(run.id == selectedRunID ? "Opens the club page" : "Selects this club")
            }
            PinTail()
                .fill(Theme.ink)
                .frame(width: 12, height: 7)
                .padding(.top, -4)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}

private struct TimePill: View {
    let run: ClubRun
    let isSelected: Bool

    var body: some View {
        let isRun = run.options.contains { $0.event.isRun }
        let parts = run.timeParts
        HStack(spacing: 3) {
            if run.options.contains(where: { $0.event.joined }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
            }
            Text("\(parts.time) \(parts.period)")
                .font(FRCFont.mono(isSelected ? 14 : 12, .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ground)
        .padding(.horizontal, isSelected ? 12 : 9)
        .frame(height: isSelected ? 34 : 28)
        .background(Capsule().fill(isSelected ? Theme.accent : (isRun ? Theme.ink : Theme.mid)))
        .overlay(Capsule().strokeBorder(isSelected ? Theme.ink : Theme.surface, lineWidth: isSelected ? 1.5 : 2))
        // Grow the tap target toward 44pt without changing the drawn size.
        .padding(.vertical, isSelected ? 5 : 8)
        .contentShape(Rectangle())
        .padding(.vertical, isSelected ? -5 : -8)
    }
}

private struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension LocationCluster {
    var accessibilityTitle: String {
        runs.map { "\($0.club.name) at \($0.timeParts.time) \($0.timeParts.period)" }.joined(separator: ", ")
    }
}

/// Asks for "While Using" location once, so the map can show the athlete's position.
@MainActor
final class LocationPermission {
    private let manager = CLLocationManager()

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}
