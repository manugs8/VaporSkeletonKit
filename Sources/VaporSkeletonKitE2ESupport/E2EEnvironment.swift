import Foundation

/// Dónde encuentra una suite E2E el servidor bajo test — HTTP/MCP real a través de la
/// red vía ``E2EHTTPClient``/``E2EMCPClient``, nunca una `Application` en proceso.
///
/// Lee `E2E_BASE_URL`, con la dirección local por defecto de `swift run` como valor por
/// defecto, de modo que los tests E2E funcionen contra un servidor arrancado a mano. En
/// pruebas locales o en entornos equivalentes de desarrollo.
public enum E2EEnvironment {
    /// - Precondition: si `E2E_BASE_URL` está definida, debe ser una URL válida. Fallar
    ///   rápido con un mensaje claro es preferible a adivinar o a caer silenciosamente
    ///   en el valor por defecto, que dejaría una suite E2E apuntando al servidor
    ///   equivocado sin ningún aviso.
    public static var baseURL: URL {
        guard let raw = ProcessInfo.processInfo.environment["E2E_BASE_URL"] else {
            return URL(string: "http://127.0.0.1:8080")!
        }
        guard let url = URL(string: raw) else {
            fatalError("E2E_BASE_URL está definida como \"\(raw)\", que no es una URL válida.")
        }
        return url
    }
}
