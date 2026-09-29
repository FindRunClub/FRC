import Foundation

/// A Strava route. Events embed a summary (name + `summary_polyline`);
/// `GET /routes/{id}` adds distance, elevation and the full-detail polyline.
public struct StravaRoute: Hashable, Sendable, Decodable {
    public let id: StravaID?
    public let name: String?
    /// Meters.
    public let distance: Double?
    /// Meters.
    public let elevationGain: Double?
    /// Seconds.
    public let estimatedMovingTime: Double?
    public let summaryPolyline: String?
    public let detailedPolyline: String?

    public init(
        id: StravaID? = nil,
        name: String? = nil,
        distance: Double? = nil,
        elevationGain: Double? = nil,
        estimatedMovingTime: Double? = nil,
        summaryPolyline: String? = nil,
        detailedPolyline: String? = nil
    ) {
        self.id = id
        self.name = name
        self.distance = distance
        self.elevationGain = elevationGain
        self.estimatedMovingTime = estimatedMovingTime
        self.summaryPolyline = summaryPolyline
        self.detailedPolyline = detailedPolyline
    }

    enum CodingKeys: String, CodingKey {
        case id
        case idString = "id_str"
        case name
        case distance
        case elevationGain = "elevation_gain"
        case estimatedMovingTime = "estimated_moving_time"
        case map
    }

    enum MapKeys: String, CodingKey {
        case summaryPolyline = "summary_polyline"
        case polyline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Prefer the string form: the numeric `id` can exceed what JSON numbers carry exactly.
        id = container.lenient(String.self, forKey: .idString).map { StravaID($0) } ?? container.lenient(StravaID.self, forKey: .id)
        name = container.lenient(String.self, forKey: .name)
        distance = container.lenient(Double.self, forKey: .distance)
        elevationGain = container.lenient(Double.self, forKey: .elevationGain)
        estimatedMovingTime = container.lenient(Double.self, forKey: .estimatedMovingTime)

        let map = try? container.nestedContainer(keyedBy: MapKeys.self, forKey: .map)
        summaryPolyline = map?.lenient(String.self, forKey: .summaryPolyline)
        detailedPolyline = map?.lenient(String.self, forKey: .polyline)
    }

    /// The best available path for drawing the route on a map.
    public var coordinates: [Coordinate] {
        for encoded in [detailedPolyline, summaryPolyline] {
            if let encoded, !encoded.isEmpty {
                let decoded = Polyline.decode(encoded)
                if decoded.count > 1 { return decoded }
            }
        }
        return []
    }

    /// Strava's distance when known; otherwise measured along the map line.
    /// Events only embed the line, so this lets lists filter by distance
    /// without fetching every route (summary lines run a little short).
    public var estimatedDistance: Double? {
        if let distance, distance > 0 { return distance }
        let path = coordinates
        return path.count > 1 ? path.pathLength : nil
    }

    /// Starts and ends within ~250 m of each other.
    public var isLoop: Bool {
        let path = coordinates
        guard let first = path.first, let last = path.last, path.count > 2 else { return false }
        return first.distance(to: last) < 250
    }

    /// "5 mi loop", "3.1 mi", or the route's name when the distance is unknown.
    public var optionLabel: String {
        guard let meters = estimatedDistance else { return name ?? "Route" }
        let miles = meters / 1_609.344
        let rounded = (miles * 10).rounded() / 10
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(number) mi" + (isLoop ? " loop" : "")
    }

    /// Fills in fields missing here from `other` (used to merge the embedded
    /// summary with the full route fetched later).
    public func merged(with other: StravaRoute) -> StravaRoute {
        StravaRoute(
            id: id ?? other.id,
            name: name ?? other.name,
            distance: distance ?? other.distance,
            elevationGain: elevationGain ?? other.elevationGain,
            estimatedMovingTime: estimatedMovingTime ?? other.estimatedMovingTime,
            summaryPolyline: summaryPolyline ?? other.summaryPolyline,
            detailedPolyline: detailedPolyline ?? other.detailedPolyline
        )
    }
}
