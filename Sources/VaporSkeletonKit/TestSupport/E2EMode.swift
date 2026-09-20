import Vapor
import Fluent
import SQLKit

/// Representa una casuística de estado predefinida que el entorno E2E requiere antes de lanzar una prueba.
public protocol E2EScenario: Sendable {
    func apply(req: Request) async throws
}

/// Define cómo el proyecto consumidor mapeará el identificador recibido (ej. "populated_dashboard")
/// a sus casos de uso y dominios para preparar el escenario.
public protocol E2EScenarioFactory: Sendable {
    func make(scenario: String) throws -> any E2EScenario
}

/// Request de preparación de estado recibida en el endpoint de E2E.
public struct PrepareScenarioRequest: Content, Sendable {
    public let scenario: String
    public let reset: Bool

    public init(scenario: String, reset: Bool) {
        self.scenario = scenario
        self.reset = reset
    }
}

/// Un fallo al intentar activar el modo E2E en un entorno no seguro.
public enum E2EModeError: Error, CustomStringConvertible, Sendable {
    /// `registerE2EMode` se llamó con `app.environment == .production`.
    case refusedInProduction

    public var description: String {
        switch self {
        case .refusedInProduction:
            return "registerE2EMode fue llamado con app.environment == .production. " +
                "Los endpoints /e2e/prepare (que puede truncar todas las tablas) y " +
                "/_test/fault nunca deben exponerse en producción — revisa qué " +
                "condición activa E2E Mode en tu configure(_:)."
        }
    }
}

/// Activa las capacidades del entorno E2E, habilitando tanto la inyección de fallos como el
/// reseteo y preparación de escenarios en base de datos.
///
/// Se niega a activarse — lanzando ``E2EModeError/refusedInProduction`` en vez de
/// registrar ninguna ruta — cuando `app.environment == .production`. Es la única
/// barrera real contra una activación accidental: la condición que decide *cuándo*
/// llamar a esta función (una variable de entorno, un flag de build...) sigue siendo
/// responsabilidad del proyecto consumidor, pero un error en esa condición ya no puede
/// exponer `/e2e/prepare` (que puede truncar todas las tablas) ni `/_test/fault` en
/// un despliegue real.
///
/// - Throws: ``E2EModeError/refusedInProduction`` si `app.environment == .production`.
public func registerE2EMode(_ app: Application, scenarioFactory: any E2EScenarioFactory) throws {
    guard app.environment != .production else {
        throw E2EModeError.refusedInProduction
    }

    app.logger.warning("E2E Mode is live (includes /e2e/prepare and /_test/fault). Never use this in production.")

    // 1. Inyección de fallos
    registerTestFaultInjection(app)
    
    // 2. Controlador de Escenarios E2E
    app.post("e2e", "prepare") { req async throws -> HTTPStatus in
        let body = try req.content.decode(PrepareScenarioRequest.self)
        
        if body.reset {
            req.logger.info("Truncating application tables...")
            if let sql = req.db as? any SQLDatabase {
                // Borra en cascada todas las tablas creadas en el schema public,
                // respetando la tabla de migraciones para que fluent siga funcionando.
                let query = """
                DO $$ DECLARE
                    r RECORD;
                BEGIN
                    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = current_schema() AND tablename <> '_fluent_migrations') LOOP
                        EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' CASCADE';
                    END LOOP;
                END $$;
                """
                try await sql.raw(SQLQueryString(stringLiteral: query)).run()
            } else {
                req.logger.warning("Database is not SQLDatabase; skipping truncate.")
            }
        }
        
        let scenario = try scenarioFactory.make(scenario: body.scenario)
        try await scenario.apply(req: req)
        
        return .ok
    }
}
