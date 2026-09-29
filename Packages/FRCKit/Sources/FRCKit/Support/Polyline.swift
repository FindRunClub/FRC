import Foundation

/// Google's encoded polyline algorithm, which Strava uses for route maps
/// (`map.summary_polyline` and `map.polyline`).
public enum Polyline {
    public static func decode(_ encoded: String) -> [Coordinate] {
        let bytes = Array(encoded.utf8)
        var coordinates: [Coordinate] = []
        var index = 0
        var latitude = 0
        var longitude = 0

        while index < bytes.count {
            guard let deltaLatitude = nextValue(in: bytes, index: &index),
                  let deltaLongitude = nextValue(in: bytes, index: &index)
            else { break }
            latitude += deltaLatitude
            longitude += deltaLongitude
            coordinates.append(Coordinate(latitude: Double(latitude) / 1e5, longitude: Double(longitude) / 1e5))
        }
        return coordinates
    }

    public static func encode(_ coordinates: [Coordinate]) -> String {
        var output = ""
        var previousLatitude = 0
        var previousLongitude = 0
        for coordinate in coordinates {
            let latitude = Int((coordinate.latitude * 1e5).rounded())
            let longitude = Int((coordinate.longitude * 1e5).rounded())
            output += encodeValue(latitude - previousLatitude)
            output += encodeValue(longitude - previousLongitude)
            previousLatitude = latitude
            previousLongitude = longitude
        }
        return output
    }

    /// Reads one zig-zag encoded value; returns nil if the input is truncated or malformed.
    private static func nextValue(in bytes: [UInt8], index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while index < bytes.count {
            let chunk = Int(bytes[index]) - 63
            index += 1
            guard chunk >= 0, shift < 60 else { return nil }
            result |= (chunk & 0x1F) << shift
            shift += 5
            if chunk < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
        }
        return nil
    }

    private static func encodeValue(_ value: Int) -> String {
        var remaining = value < 0 ? ~(value << 1) : (value << 1)
        var output = ""
        while remaining >= 0x20 {
            output.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (remaining & 0x1F)) + 63)))
            remaining >>= 5
        }
        output.unicodeScalars.append(UnicodeScalar(UInt8(remaining + 63)))
        return output
    }
}
