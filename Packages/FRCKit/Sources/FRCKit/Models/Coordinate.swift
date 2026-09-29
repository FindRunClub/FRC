import Foundation

/// A latitude/longitude pair. FRCKit stays free of CoreLocation so it can be
/// tested anywhere; the app converts to `CLLocationCoordinate2D` at the edge.
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Builds a coordinate from Strava's `[lat, lng]` arrays, rejecting empty
    /// arrays and the `[0, 0]` placeholder.
    init?(latLng: [Double]?) {
        guard let latLng, latLng.count == 2 else { return nil }
        let latitude = latLng[0]
        let longitude = latLng[1]
        guard (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              !(latitude == 0 && longitude == 0)
        else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }
}

/// The smallest latitude/longitude box containing a set of coordinates.
public struct CoordinateBounds: Hashable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init?(_ coordinates: [Coordinate]) {
        guard let first = coordinates.first else { return nil }
        var bounds = (minLat: first.latitude, maxLat: first.latitude, minLng: first.longitude, maxLng: first.longitude)
        for coordinate in coordinates.dropFirst() {
            bounds.minLat = min(bounds.minLat, coordinate.latitude)
            bounds.maxLat = max(bounds.maxLat, coordinate.latitude)
            bounds.minLng = min(bounds.minLng, coordinate.longitude)
            bounds.maxLng = max(bounds.maxLng, coordinate.longitude)
        }
        minLatitude = bounds.minLat
        maxLatitude = bounds.maxLat
        minLongitude = bounds.minLng
        maxLongitude = bounds.maxLng
    }

    public var center: Coordinate {
        Coordinate(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    /// Span in degrees, padded so pins at the edges aren't clipped, and never
    /// smaller than `minimumSpan` so a single pin doesn't zoom to street level.
    public func paddedSpan(padding: Double = 1.4, minimumSpan: Double = 0.02) -> (latitudeDelta: Double, longitudeDelta: Double) {
        (
            latitudeDelta: max((maxLatitude - minLatitude) * padding, minimumSpan),
            longitudeDelta: max((maxLongitude - minLongitude) * padding, minimumSpan)
        )
    }
}

extension Coordinate {
    /// Great-circle distance in meters.
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLng = (other.longitude - longitude) * .pi / 180
        let h = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }
}

extension Array where Element == Coordinate {
    /// Length of the path through these points, in meters.
    public var pathLength: Double {
        zip(self, dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
    }
}
