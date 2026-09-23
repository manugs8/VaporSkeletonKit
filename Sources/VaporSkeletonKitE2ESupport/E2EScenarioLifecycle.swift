import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Un fallo al preparar el escenario de un servidor E2E persistente — nunca `fatalError`:
/// un test debe poder fallar con un mensaje legible, no tumbar el proceso entero (lo que
/// además impediría que el resto de tests de ese mismo proceso reporten su propio
/// resultado).
public enum E2EPersistentServerError: Error, CustomStringConvertible {
    case missingScenario(environmentVariable: String)
    case serverUnreachable(baseURL: URL, underlying: any Error)

    public var description: String {
        switch self {
        case .missingScenario(let environmentVariable):
            return "\(environmentVariable) no está definida — revisa la Configuration del test plan activo."
        case .serverUnreachable(let baseURL, let underlying):
            return """
                No se pudo conectar con el servidor E2E en \(baseURL). ¿Está arrancado? \
                (\(underlying))
                """
        }
    }
}

/// Prepara, una sola vez por proceso, el escenario que la Configuration del test plan
/// activo declara en una variable de entorno (`E2E_SCENARIO` por defecto) — contra un
/// servidor ya en ejecución, no uno que este tipo arranque. Deliberadamente agnóstico del
/// tipo de escenario de cada proyecto consumidor (`Components.Schemas.E2EScenarioName`
/// generado por `swift-openapi-generator` es distinto en cada uno): recibe un closure
/// `prepare` que traduce el `String` bruto de la variable de entorno a lo que ese
/// `/e2e/prepare` concreto necesite, en vez de asumir ningún tipo o ruta.
///
/// Uso típico, en el proyecto consumidor:
/// ```swift
/// let scenarioLifecycle = E2EScenarioLifecycle { raw, client in
///     guard let scenario = Components.Schemas.E2EScenarioName(rawValue: raw) else {
///         throw MyOwnUnknownScenarioError(raw)
///     }
///     try await client.prepareScenario(scenario, reset: true)
/// }
///
/// func withPersistentServer(_ test: (E2EHTTPClient) async throws -> Void) async throws {
///     try await VaporSkeletonKitE2ESupport.withPersistentServer(scenarioLifecycle, test)
/// }
/// ```
///
/// Un `Task` perezoso (no un actor, ni contador de referencias) es suficiente: en el
/// modelo de "un `.xctestplan` por escenario" que motivó este tipo, cada test plan es su
/// propia invocación de `xcodebuild test`, así que "una vez por proceso" ya significa
/// "una vez por fase" — no hace falta coordinar entre invocaciones concurrentes porque no
/// las hay dentro de un mismo proceso. Todo test que llame a ``wait()`` recibe el mismo
/// resultado memoizado por `Task`, incluida la misma falla si algo salió mal.
public final class E2EScenarioLifecycle: Sendable {
    private let task: Task<Void, any Error>

    /// - Parameters:
    ///   - environmentVariable: El nombre de la variable de entorno que declara el
    ///     escenario activo — pensada para venir de la Configuration de un `.xctestplan`.
    ///   - baseURL: El servidor E2E persistente. Por defecto, ``E2EEnvironment/baseURL``.
    ///   - prepare: Traduce el valor bruto de `environmentVariable` a una llamada real
    ///     contra `client` — normalmente un `POST /e2e/prepare` propio del proyecto. Se
    ///     ejecuta como mucho una vez por proceso.
    public init(
        environmentVariable: String = "E2E_SCENARIO",
        baseURL: URL = E2EEnvironment.baseURL,
        prepare: @escaping @Sendable (_ rawScenario: String, _ client: E2EHTTPClient) async throws -> Void
    ) {
        task = Task {
            guard let raw = ProcessInfo.processInfo.environment[environmentVariable] else {
                throw E2EPersistentServerError.missingScenario(environmentVariable: environmentVariable)
            }
            let client = E2EHTTPClient(baseURL: baseURL)
            do {
                try await prepare(raw, client)
            } catch let error as URLError {
                throw E2EPersistentServerError.serverUnreachable(baseURL: baseURL, underlying: error)
            }
        }
    }

    /// Espera a que la preparación termine — o falle, con un ``E2EPersistentServerError``
    /// legible. Segura de llamar desde varios tests: comparten la misma `Task` memoizada.
    public func wait() async throws {
        try await task.value
    }
}

/// Espera a que `lifecycle` termine de preparar su escenario y entrega un `E2EHTTPClient`
/// ya listo contra ese mismo servidor persistente — sin arrancar ni apagar ningún
/// servidor.
public func withPersistentServer(
    _ lifecycle: E2EScenarioLifecycle,
    baseURL: URL = E2EEnvironment.baseURL,
    _ test: (E2EHTTPClient) async throws -> Void
) async throws {
    try await lifecycle.wait()
    try await test(E2EHTTPClient(baseURL: baseURL))
}
