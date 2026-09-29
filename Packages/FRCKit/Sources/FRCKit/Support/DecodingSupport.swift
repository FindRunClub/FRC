import Foundation

// The club events endpoints are not part of Strava's published API reference,
// so decoding is deliberately forgiving: a field that changes type or goes
// missing becomes `nil` instead of failing the whole response.

extension KeyedDecodingContainer {
    /// Decodes a value if present and well-formed, otherwise returns `nil`.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// Decodes a string that should hold an absolute http(s) URL.
    /// Strava sends placeholders like "avatar/athlete/large.png" for athletes
    /// without a photo; those become `nil` so the UI can show initials instead.
    func lenientURL(forKey key: Key) -> URL? {
        guard let string = lenient(String.self, forKey: key),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }
}

/// Decodes a JSON array, silently dropping elements that fail to decode.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]
    /// Number of elements in the JSON, including dropped ones (for pagination).
    var rawCount: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var rawCount = 0
        while !container.isAtEnd {
            rawCount += 1
            if (try? container.decodeNil()) == true {
                continue
            }
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if (try? container.decode(SkippedElement.self)) == nil {
                // A failed decode doesn't advance the container; if even skipping
                // fails, stop rather than loop forever.
                break
            }
        }
        self.elements = elements
        self.rawCount = rawCount
    }

    private struct SkippedElement: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

enum StravaDateParser {
    /// Parses the ISO 8601 timestamps Strava uses ("2026-03-24T08:00:00Z"),
    /// with or without fractional seconds.
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
