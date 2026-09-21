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
public enum E2EModeError: Error, CustomStringConvertible, Sendable, Equatable {
    /// `registerE2EMode` se llamó con un `app.environment` distinto de `.testing`;
    /// `current` es el nombre del entorno recibido.
    case requiresTestingEnvironment(current: String)

    public var description: String {
        switch self {
        case .requiresTestingEnvironment(let current):
            return "registerE2EMode solo se activa con app.environment == .testing, y se " +
                "llamó con \"\(current)\". Los endpoints /e2e/prepare (que puede truncar " +
                "todas las tablas) y /_test/fault nunca deben exponerse fuera de un entorno " +
                "de test — arranca la instancia E2E con --env testing (o VAPOR_ENV=testing), " +
                "o revisa qué condición activa E2E Mode en tu configure(_:)."
        }
    }
}

/// Activa las capacidades del entorno E2E, habilitando tanto la inyección de fallos como el
/// reseteo y preparación de escenarios en base de datos.
///
/// Este código vive en el módulo de producción a propósito: las suites E2E se ejecutan
/// contra el mismo artefacto que se despliega (misma imagen, ninguna compilación
/// específica para E2E), así que el binario tiene que poder montar estas rutas. Lo que
/// garantiza que nunca estén disponibles en producción es esta barrera, no el módulo.
///
/// Solo se activa cuando `app.environment == .testing` (`serve --env testing`,
/// `VAPOR_ENV=testing` o `Application.make(.testing)`). En cualquier otro entorno lanza
/// ``E2EModeError/requiresTestingEnvironment(current:)`` en vez de registrar ninguna ruta,
/// incluido `.development`, el que usa Vapor por defecto cuando el proceso arranca sin
/// `--env`: un despliegue de producción que olvide declararse como tal tampoco puede
/// exponerlas. La condición que decide *cuándo* llamar a esta función (una variable de
/// entorno propia, p. ej.) sigue siendo del proyecto consumidor; un error en ella se
/// convierte en un fallo de arranque explícito, no en un servidor con estas rutas abiertas.
///
/// - Throws: ``E2EModeError/requiresTestingEnvironment(current:)`` si
///   `app.environment != .testing`.
public func registerE2EMode(_ app: Application, scenarioFactory: any E2EScenarioFactory) throws {
    guard app.environment == .testing else {
        throw E2EModeError.requiresTestingEnvironment(current: app.environment.name)
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
        
        let scenario: any E2EScenario
        do {
            scenario = try scenarioFactory.make(scenario: body.scenario)
        } catch {
            // El escenario lo elige el cliente que llama a /e2e/prepare — si la
            // factory lo rechaza (p. ej. no reconoce el identificador), es un dato de
            // entrada inválido, no un fallo interno: 400, no el 500 por defecto de
            // Vapor ante un error no reconocido como AbortError.
            throw Abort(.badRequest, reason: "Unknown E2E scenario \"\(body.scenario)\": \(error)")
        }
        try await scenario.apply(req: req)
        
        return .ok
    }
}
