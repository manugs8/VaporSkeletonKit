import Foundation
import Vapor

/// Estado compartido para `TestFaultInjectionMiddleware`.
actor FaultInjectionStore {
    struct ArmedFault: Sendable {
        let status: Int
        let delayMilliseconds: Int
        /// Cuerpo crudo a devolver en vez de `FaultBody` por defecto — `nil` conserva el
        /// comportamiento previo.
        let body: Data?
        /// Cabeceras adicionales a añadir a la respuesta cuando `body` no es `nil`.
        let headers: [String: String]?
    }

    private var armed: [String: ArmedFault] = [:]

    func arm(
        method: String, path: String, status: Int, delayMilliseconds: Int,
        body: Data? = nil, headers: [String: String]? = nil
    ) {
        armed[Self.key(method: method, path: path)] = ArmedFault(
            status: status, delayMilliseconds: delayMilliseconds, body: body, headers: headers
        )
    }

    func consume(method: String, path: String) -> ArmedFault? {
        armed.removeValue(forKey: Self.key(method: method, path: path))
    }

    func clearAll() {
        armed.removeAll()
    }

    private static func key(method: String, path: String) -> String {
        "\(method.uppercased()) \(path)"
    }
}

/// Middleware para inyectar fallos en las respuestas durante tests.
struct TestFaultInjectionMiddleware: AsyncMiddleware {
    static let controlPath = "/_test/fault"

    /// Tope superior para `delayMilliseconds` — un test que arma un fallo con un delay
    /// desmedido (o negativo, por error) no debería poder colgar la suite entera.
    static let maxDelayMilliseconds = 30_000

    /// Tope superior (en bytes UTF-8) para `ArmRequest.body` — protege contra un `body`
    /// desmedido (por error o adrede) de la misma forma que `maxDelayMilliseconds` protege
    /// contra un delay desmedido.
    static let maxBodyBytes = 64 * 1024

    struct ArmRequest: Content {
        let method: String
        let path: String
        let status: Int
        let delayMilliseconds: Int?
        /// Cuerpo de respuesta a devolver en vez de `FaultBody` cuando el fallo se
        /// consuma — texto crudo (normalmente JSON ya serializado por el llamador), no
        /// un objeto a volver a codificar. Permite que un consumidor arme una respuesta
        /// que imite el contrato de error real de su propia app (p. ej. el
        /// `{"error": true, "reason": "..."}` de un `AbortError` de Vapor) en vez de
        /// quedarse con la forma fija de `FaultBody`. `nil` (el valor por defecto)
        /// conserva el comportamiento previo.
        let body: String?
        /// Cabeceras adicionales a añadir a la respuesta cuando `body` no es `nil` — se
        /// ignoran si `body` es `nil`. Incluir `Content-Type` aquí sobreescribe el
        /// `application/json` que se añade por defecto cuando hay `body`.
        let headers: [String: String]?

        // Inicializador explícito con valores por defecto para `body`/`headers` — el
        // sintetizado por Swift para un `struct` con propiedades sin valor por defecto
        // exigiría pasarlas siempre, rompiendo cada construcción existente de
        // `ArmRequest(...)` en tests que no conocen estos campos nuevos.
        init(method: String, path: String, status: Int, delayMilliseconds: Int?, body: String? = nil, headers: [String: String]? = nil) {
            self.method = method
            self.path = path
            self.status = status
            self.delayMilliseconds = delayMilliseconds
            self.body = body
            self.headers = headers
        }
    }

    struct FaultBody: Content {
        let error: String
        let status: Int
    }

    let store: FaultInjectionStore

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let path = request.url.path

        if path == Self.controlPath {
            switch request.method {
            case .POST:
                // Este middleware se instala en `.beginning`, por fuera de ErrorMiddleware:
                // un error que se escape de aquí no se convierte en respuesta HTTP, sino
                // que Vapor cierra la conexión. Un cuerpo malformado es un 400, no eso.
                let armRequest: ArmRequest
                do {
                    armRequest = try request.content.decode(ArmRequest.self)
                } catch {
                    return Self.badRequest("Invalid fault request body: \(error)")
                }
                guard (100...599).contains(armRequest.status) else {
                    return Self.badRequest("status must be in 100...599, got \(armRequest.status).")
                }
                let delayMilliseconds = armRequest.delayMilliseconds ?? 0
                guard (0...Self.maxDelayMilliseconds).contains(delayMilliseconds) else {
                    return Self.badRequest(
                        "delayMilliseconds must be in 0...\(Self.maxDelayMilliseconds), got \(delayMilliseconds)."
                    )
                }
                if let body = armRequest.body, body.utf8.count > Self.maxBodyBytes {
                    return Self.badRequest("body must be at most \(Self.maxBodyBytes) bytes, got \(body.utf8.count).")
                }
                await store.arm(
                    method: armRequest.method,
                    path: armRequest.path,
                    status: armRequest.status,
                    delayMilliseconds: delayMilliseconds,
                    body: armRequest.body.map { Data($0.utf8) },
                    headers: armRequest.headers
                )
                return Response(status: .ok)
            case .DELETE:
                await store.clearAll()
                return Response(status: .ok)
            default:
                break
            }
        }

        if let fault = await store.consume(method: request.method.rawValue, path: path) {
            if fault.delayMilliseconds > 0 {
                try await Task.sleep(for: .milliseconds(fault.delayMilliseconds))
            }
            let response = Response(status: HTTPResponseStatus(statusCode: fault.status))
            if let body = fault.body {
                response.headers.replaceOrAdd(name: .contentType, value: "application/json")
                for (name, value) in fault.headers ?? [:] {
                    response.headers.replaceOrAdd(name: name, value: value)
                }
                response.body = .init(data: body)
            } else {
                try response.content.encode(FaultBody(error: "test_fault_injected", status: fault.status))
            }
            return response
        }

        return try await next.respond(to: request)
    }

    private static func badRequest(_ reason: String) -> Response {
        let response = Response(status: .badRequest)
        try? response.content.encode(FaultBody(error: reason, status: 400))
        return response
    }
}

/// Registra el endpoint /_test/fault para inyectar fallos en tests E2E y de Integración.
/// Se usa internamente dentro de `registerE2EMode`.
func registerTestFaultInjection(_ app: Application) {
    app.middleware.use(TestFaultInjectionMiddleware(store: FaultInjectionStore()), at: .beginning)
}
