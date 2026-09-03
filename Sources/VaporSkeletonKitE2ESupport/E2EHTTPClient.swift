import Foundation
#if canImport(FoundationNetworking)
// URLSession/URLRequest/HTTPURLResponse live in a separate module on Linux (they're
// still part of Foundation on Apple platforms) — needed explicitly for E2E suites that
// run their production Docker image under a Linux CI runner.
import FoundationNetworking
#endif

/// A failure returned by the real HTTP server, as opposed to a transport-level error.
public enum E2EHTTPError: Error, CustomStringConvertible {
    case unexpectedStatus(Int, body: String)

    public var description: String {
        switch self {
        case .unexpectedStatus(let status, let body):
            return "Unexpected HTTP status \(status): \(body)"
        }
    }
}

/// A minimal REST client for E2E tests (and any deterministic seed sharing their
/// support code), talking to a real running server over the network — never an
/// in-process `Application`, unlike `VaporTesting`-based integration tests.
public struct E2EHTTPClient: Sendable {
    public struct Response: Sendable {
        public let status: Int
        public let body: Data
    }

    public let baseURL: URL
    private let authToken: @Sendable () async throws -> String?
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: The server to talk to. Defaults to ``E2EEnvironment/baseURL``.
    ///   - authToken: Produces the bearer token attached to authenticated requests, or
    ///     `nil` to send no `Authorization` header. Called on every authenticated
    ///     request, not cached — this function doesn't assume any particular auth
    ///     package. Defaults to never attaching a token.
    ///   - session: The `URLSession` to issue requests on. Defaults to `.shared`;
    ///     overridable in tests.
    public init(
        baseURL: URL = E2EEnvironment.baseURL,
        authToken: @escaping @Sendable () async throws -> String? = { nil },
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
    }

    /// Sends a request, optionally attaching `Authorization: Bearer <token>` from
    /// ``authToken``.
    ///
    /// - Parameter authenticated: Pass `false` to intentionally omit the token, even if
    ///   ``authToken`` would produce one — used by "rejects unauthenticated requests"
    ///   scenarios.
    @discardableResult
    public func send(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token = try await authToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return Response(status: status, body: data)
    }

    public func get(_ path: String, authenticated: Bool = true) async throws -> Response {
        try await send("GET", path, authenticated: authenticated)
    }

    /// Sends a `POST` with a JSON-encoded body and decodes a JSON response, throwing
    /// ``E2EHTTPError`` if the server didn't respond `200`.
    public func post<Body: Encodable, Decoded: Decodable>(
        _ path: String,
        json: Body,
        as: Decoded.Type,
        authenticated: Bool = true
    ) async throws -> Decoded {
        let body = try JSONEncoder.e2e.encode(json)
        let response = try await send("POST", path, body: body, authenticated: authenticated)
        guard response.status == 200 else {
            throw E2EHTTPError.unexpectedStatus(response.status, body: String(decoding: response.body, as: UTF8.self))
        }
        return try JSONDecoder.e2e.decode(Decoded.self, from: response.body)
    }

    public func get<Decoded: Decodable>(_ path: String, as: Decoded.Type, authenticated: Bool = true) async throws
        -> Decoded
    {
        let response = try await get(path, authenticated: authenticated)
        guard response.status == 200 else {
            throw E2EHTTPError.unexpectedStatus(response.status, body: String(decoding: response.body, as: UTF8.self))
        }
        return try JSONDecoder.e2e.decode(Decoded.self, from: response.body)
    }
}

extension JSONEncoder {
    public static let e2e: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    public static let e2e: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
