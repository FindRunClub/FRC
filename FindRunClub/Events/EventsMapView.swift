import CoreLocation
import FRCKit
import MapKit
import SwiftUI

/// Apple Maps (MapKit): free, no API key. Each pin is just the start time;
/// tapping a time opens that run's details.
struct EventsMapView: View {
    let clusters: [LocationCluster]
    let selectedDay: LocalDay
    let onSelect: (EventOccurrence) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var locationPermission = LocationPermission()

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(clusters) { cluster in
                Annotation(cluster.accessibilityTitle, coordinate: cluster.coordinate.locationCoordinate, anchor: .bottom) {
                    TimePin(cluster: cluster, onSelect: onSelect)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            locationPermission.requestIfNeeded()
            frameClusters(animated: false)
        }
        .onChange(of: framingKey) {
            frameClusters(animated: true)
        }
    }

    /// Changes whenever the day or its set of pins changes.
    private var framingKey: String {
        ([selectedDay.id] + clusters.map(\.id)).joined(separator: "|")
    }

    /// Zooms to fit the day's pins; leaves the camera alone on empty days.
    private func frameClusters(animated: Bool) {
        guard let bounds = CoordinateBounds(clusters.map(\.coordinate)) else { return }
        let span = bounds.paddedSpan(padding: 1.6, minimumSpan: 0.02)
        let region = MKCoordinateRegion(
            center: bounds.center.locationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: span.latitudeDelta, longitudeDelta: span.longitudeDelta)
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                position = .region(region)
            }
        } else {
            position = .region(region)
        }
    }
}

/// One or more time buttons stacked over a start location.
struct TimePin: View {
    let cluster: LocationCluster
    let onSelect: (EventOccurrence) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(cluster.occurrences) { occurrence in
                    Button {
                        onSelect(occurrence)
                    } label: {
                        HStack(spacing: 4) {
                            if occurrence.event.joined {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.bold))
                            }
                            Text(occurrence.timeText)
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(occurrence.event.isRun ? Theme.stravaOrange : Theme.otherActivity))
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(occurrence.timeText), \(occurrence.event.title), \(occurrence.club.name)")
                    .accessibilityHint("Shows event details")
                }
            }
            .padding(cluster.occurrences.count > 1 ? 4 : 0)
            .background {
                if cluster.occurrences.count > 1 {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.thinMaterial)
                }
            }

            PinPointer()
                .fill(cluster.occurrences.first?.event.isRun == false ? Theme.otherActivity : Theme.stravaOrange)
                .frame(width: 14, height: 8)
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

private struct PinPointer: Shape {
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
        occurrences.map { "\($0.club.name) at \($0.timeText)" }.joined(separator: ", ")
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
