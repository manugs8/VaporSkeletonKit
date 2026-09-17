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

/// Middleware para inyectar fallos en los resposnes durante tests.
/// Solo se activa si `TEST_FAULT_INJECTION_ENABLED=true` (ver ADR 0011).
struct TestFaultInjectionMiddleware: AsyncMiddleware {
    static let controlPath = "/_test/fault"

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
                let armRequest = try request.content.decode(ArmRequest.self)
                await store.arm(
                    method: armRequest.method,
                    path: armRequest.path,
                    status: armRequest.status,
                    delayMilliseconds: armRequest.delayMilliseconds ?? 0
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
}

/// Registra el endpoint /_test/fault para inyectar fallos en tests E2E y de Integración si la variable
/// de entorno TEST_FAULT_INJECTION_ENABLED es verdara. Debe ser llamada antes de cualquier middleware que
/// intercepte o valide el estado de la request (como configuración de WorkOSBearerAuth).
public func registerTestFaultInjection(_ app: Application) {
    if Environment.get("TEST_FAULT_INJECTION_ENABLED").flatMap(Bool.init) == true {
        app.logger.warning("TEST_FAULT_INJECTION_ENABLED=true — /_test/fault is live. Never set this in production.")
        app.middleware.use(TestFaultInjectionMiddleware(store: FaultInjectionStore()), at: .beginning)
    } else {
        app.logger.info("TEST_FAULT_INJECTION_ENABLED is not set to true — /_test/fault is not mounted.")
    }
}
