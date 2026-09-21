import Foundation
import Testing

@testable import VaporSkeletonKitE2ESupport

/// Ver V3 en `docs/InformeDeAuditoria.md`: `E2EEnvironment.baseURL` hacía force-unwrap
/// de una `E2E_BASE_URL` mal formada sin ningún diagnóstico legible. Los dos casos que
/// no crashean (sin definir / válida) se cubren aquí; el caso mal formado ahora falla
/// con un `fatalError` con mensaje claro en vez de un `!` desnudo — no verificable con
/// un test normal, ya que termina el proceso.
///
/// `.serialized`: ambos tests mutan la variable de entorno global `E2E_BASE_URL` — sin
/// serializar, Swift Testing los ejecuta en paralelo por defecto y se pisan entre sí.
@Suite("E2E Environment", .serialized)
struct E2EEnvironmentTests {
    @Test("Defaults to http://127.0.0.1:8080 when E2E_BASE_URL is unset")
    func defaultsWhenUnset() {
        let original = ProcessInfo.processInfo.environment["E2E_BASE_URL"]
        unsetenv("E2E_BASE_URL")
        defer { if let original { setenv("E2E_BASE_URL", original, 1) } }

        #expect(E2EEnvironment.baseURL == URL(string: "http://127.0.0.1:8080")!)
    }

    @Test("Uses E2E_BASE_URL when it's already a valid URL")
    func usesValidURL() {
        let original = ProcessInfo.processInfo.environment["E2E_BASE_URL"]
        setenv("E2E_BASE_URL", "https://example.com:9090", 1)
        defer {
            if let original {
                setenv("E2E_BASE_URL", original, 1)
            } else {
                unsetenv("E2E_BASE_URL")
            }
        }

        #expect(E2EEnvironment.baseURL == URL(string: "https://example.com:9090")!)
    }
}
