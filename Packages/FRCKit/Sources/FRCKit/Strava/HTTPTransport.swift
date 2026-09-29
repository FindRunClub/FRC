import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one seam between FRCKit and the network, so tests can stub responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaAPIError.invalidResponse
        }
        return (data, httpResponse)
    }
}
