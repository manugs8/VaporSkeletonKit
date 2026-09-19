import Vapor
import Fluent
import SQLKit

/// Representa un casuística de estado predefinido que el entorno E2E requiere antes de lanzar una prueba.
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

/// Activa las capacidades del entorno E2E, habilitando tanto la inyección de fallos como el
/// reseteo y preparación de escenarios en base de datos.
///
/// **ATENCIÓN:** Nunca llamar a este método en un entorno de producción.
public func registerE2EMode(_ app: Application, scenarioFactory: any E2EScenarioFactory) {
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
