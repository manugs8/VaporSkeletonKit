import Foundation

/// Dónde encuentra una suite E2E el servidor bajo test — HTTP/MCP real a través de la
/// red vía ``E2EHTTPClient``/``E2EMCPClient``, nunca una `Application` en proceso.
///
/// Lee `E2E_BASE_URL`, con la dirección local de `swift run` como valor por defecto, de
/// modo que los mismos tests E2E funcionen tanto contra un servidor arrancado a mano en
/// local como contra el equivalente en CI, sin cambiar el código del test.
public enum E2EEnvironment {
    public static var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["E2E_BASE_URL"] ?? "http://127.0.0.1:8080")!
    }
}
