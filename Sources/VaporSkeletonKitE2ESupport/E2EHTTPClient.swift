import Foundation
#if canImport(FoundationNetworking)
// URLSession/URLRequest/HTTPURLResponse viven en un módulo separado en Linux (en
// plataformas Apple siguen siendo parte de Foundation) — necesario explícitamente para
// suites E2E que ejecutan su imagen Docker de producción en un runner de CI Linux.
import FoundationNetworking
#endif

/// Un fallo devuelto por el servidor HTTP real, en contraposición a un error a nivel de
/// transporte.
public enum E2EHTTPError: Error, CustomStringConvertible {
    case unexpectedStatus(Int, body: String)

    public var description: String {
        switch self {
        case .unexpectedStatus(let status, let body):
            return "Unexpected HTTP status \(status): \(body)"
        }
    }
}

/// Un cliente REST mínimo para tests E2E (y cualquier seed determinista que comparta su
/// código de soporte), que habla con un servidor real en ejecución a través de la red
/// — nunca con una `Application` en proceso, a diferencia de los tests de integración
/// basados en `VaporTesting`.
public struct E2EHTTPClient: Sendable {
    public struct Response: Sendable {
        public let status: Int
        public let body: Data
    }

    public let baseURL: URL
    private let authToken: @Sendable () async throws -> String?
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: El servidor con el que hablar. Por defecto, ``E2EEnvironment/baseURL``.
    ///   - authToken: Produce el bearer token que se adjunta a las peticiones
    ///     autenticadas, o `nil` para no enviar ninguna cabecera `Authorization`. Se
    ///     llama en cada petición autenticada, sin cachear el resultado — esta función
    ///     no asume ningún paquete de autenticación en concreto. Por defecto, nunca
    ///     adjunta ningún token.
    ///   - session: La `URLSession` sobre la que emitir las peticiones. Por defecto,
    ///     `.shared`; sobreescribible en tests.
    public init(
        baseURL: URL = E2EEnvironment.baseURL,
        authToken: @escaping @Sendable () async throws -> String? = { nil },
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
    }

    /// Envía una petición, adjuntando opcionalmente `Authorization: Bearer <token>`
    /// desde ``authToken``.
    ///
    /// - Parameter authenticated: Pasa `false` para omitir el token deliberadamente,
    ///   incluso si ``authToken`` produciría uno — usado por los escenarios que
    ///   verifican que se rechazan las peticiones no autenticadas.
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

    /// Envía un `POST` con un cuerpo codificado en JSON y decodifica una respuesta
    /// JSON, lanzando ``E2EHTTPError`` si el servidor no respondió `200`.
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
