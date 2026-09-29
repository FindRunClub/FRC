import Foundation

/// An identifier for Strava objects whose IDs can exceed 2^53 (events, routes).
///
/// Strava sends these as JSON numbers in some places (`id`, `route_id`) and as
/// strings in others (`id_str`). Storing the decimal string keeps them exact
/// no matter which form arrives.
public struct StravaID: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ value: Int64) {
        self.rawValue = String(value)
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            rawValue = string
        } else if let int = try? container.decode(Int64.self) {
            rawValue = String(int)
        } else if let uint = try? container.decode(UInt64.self) {
            rawValue = String(uint)
        } else {
            let double = try container.decode(Double.self)
            rawValue = String(format: "%.0f", double)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}
