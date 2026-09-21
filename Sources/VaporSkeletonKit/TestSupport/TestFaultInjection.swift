import Vapor

/// Estado compartido para `TestFaultInjectionMiddleware`.
actor FaultInjectionStore {
    struct ArmedFault: Sendable {
        let status: Int
        let delayMilliseconds: Int
    }

    private var armed: [String: ArmedFault] = [:]

    func arm(method: String, path: String, status: Int, delayMilliseconds: Int) {
        armed[Self.key(method: method, path: path)] = ArmedFault(status: status, delayMilliseconds: delayMilliseconds)
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

    struct ArmRequest: Content {
        let method: String
        let path: String
        let status: Int
        let delayMilliseconds: Int?
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
                await store.arm(
                    method: armRequest.method,
                    path: armRequest.path,
                    status: armRequest.status,
                    delayMilliseconds: delayMilliseconds
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
            try response.content.encode(FaultBody(error: "test_fault_injected", status: fault.status))
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
