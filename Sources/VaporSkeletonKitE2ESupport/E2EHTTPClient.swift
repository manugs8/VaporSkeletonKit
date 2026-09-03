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
        /// Nombres de cabecera en minúsculas — HTTP no distingue mayúsculas en los
        /// nombres, así que quien consulte esto no debería tener que adivinar cómo
        /// capitalizó el servidor cada una (p. ej. `headers["content-type"]`, nunca
        /// `headers["Content-Type"]`).
        public let headers: [String: String]
    }

    /// Qué mandar como cabecera `Authorization` en una petición concreta. `.default`
    /// (el caso implícito de todos los métodos de abajo) llama a la función `authToken`
    /// dada al inicializador — así la inmensa mayoría de los escenarios (que no prueban
    /// auth en sí, solo dependen de que la petición llegue) no necesitan saber nada de
    /// esto. `.none`/`.bearer` son para los escenarios que sí prueban auth: ausencia de
    /// cabecera, o un token concreto (inválido, expirado...) en vez del que produciría
    /// `authToken`.
    public enum Authorization: Sendable {
        case `default`
        case none
        case bearer(String)
    }

    public let baseURL: URL
    private let authToken: @Sendable () async throws -> String?
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: El servidor con el que hablar. Por defecto, ``E2EEnvironment/baseURL``.
    ///   - authToken: Produce el bearer token que se adjunta a una petición cuando su
    ///     ``Authorization-swift.enum`` es `.default`, o `nil` para no enviar ninguna
    ///     cabecera `Authorization`. Se llama en cada petición `.default`, sin cachear
    ///     el resultado — esta función no asume ningún paquete de autenticación en
    ///     concreto. Por defecto, nunca adjunta ningún token.
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

    /// Envía una petición con un cuerpo arbitrario (o sin cuerpo) y un `Content-Type`
    /// explícito.
    ///
    /// - Parameter contentType: Ignorado si `body` es `nil`. Por defecto
    ///   `application/json` — pásalo explícitamente para probar el rechazo de un
    ///   `Content-Type` incompatible (la única vía para mandar otra cosa, ya que las
    ///   demás sobrecargas de este cliente fijan `application/json` a propósito).
    @discardableResult
    public func send(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        contentType: String = "application/json",
        authorization: Authorization = .default
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        switch authorization {
        case .default:
            if let token = try await authToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .none:
            break
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw E2EHTTPError.unexpectedStatus(-1, body: String(decoding: data, as: UTF8.self))
        }
        let headers = Dictionary(
            uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value -> (String, String)? in
                guard let name = key as? String, let stringValue = value as? String else { return nil }
                return (name.lowercased(), stringValue)
            }
        )
        return Response(status: http.statusCode, body: data, headers: headers)
    }

    public func get(_ path: String, authorization: Authorization = .default) async throws -> Response {
        try await send("GET", path, authorization: authorization)
    }

    /// Para endpoints sin cuerpo (p. ej. una acción `POST .../undo`).
    @discardableResult
    public func post(_ path: String, authorization: Authorization = .default) async throws -> Response {
        try await send("POST", path, authorization: authorization)
    }

    @discardableResult
    public func post(_ path: String, json body: Data, authorization: Authorization = .default) async throws
        -> Response
    {
        try await send("POST", path, body: body, authorization: authorization)
    }

    @discardableResult
    public func post(
        _ path: String, encoding body: some Encodable, authorization: Authorization = .default
    ) async throws -> Response {
        try await post(path, json: try JSONEncoder.e2e.encode(body), authorization: authorization)
    }

    @discardableResult
    public func put(_ path: String, json body: Data, authorization: Authorization = .default) async throws
        -> Response
    {
        try await send("PUT", path, body: body, authorization: authorization)
    }

    @discardableResult
    public func put(
        _ path: String, encoding body: some Encodable, authorization: Authorization = .default
    ) async throws -> Response {
        try await put(path, json: try JSONEncoder.e2e.encode(body), authorization: authorization)
    }

    /// Envía un `POST` con un cuerpo codificado en JSON y decodifica una respuesta
    /// JSON, lanzando ``E2EHTTPError`` si el servidor no respondió `200`.
    public func post<Body: Encodable, Decoded: Decodable>(
        _ path: String,
        json: Body,
        as: Decoded.Type,
        authorization: Authorization = .default
    ) async throws -> Decoded {
        let response = try await post(path, json: try JSONEncoder.e2e.encode(json), authorization: authorization)
        guard response.status == 200 else {
            throw E2EHTTPError.unexpectedStatus(response.status, body: String(decoding: response.body, as: UTF8.self))
        }
        return try JSONDecoder.e2e.decode(Decoded.self, from: response.body)
    }

    public func get<Decoded: Decodable>(
        _ path: String, as: Decoded.Type, authorization: Authorization = .default
    ) async throws -> Decoded {
        let response = try await get(path, authorization: authorization)
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
