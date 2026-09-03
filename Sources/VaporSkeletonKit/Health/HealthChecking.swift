import Fluent
import FluentPostgresDriver
import Vapor

/// Una abstracción sobre un servicio capaz de informar si sus dependencias están sanas.
///
/// Los tipos que se ajustan a este protocolo respaldan la ruta `/health` registrada por
/// ``registerHealthRoute(_:)``. Depender de este protocolo en lugar de un tipo concreto
/// mantiene el health check testeable: el código de producción puede inyectar
/// `DatabaseHealthChecker`, mientras que los tests pueden inyectar un stub que devuelva
/// un resultado fijo.
public protocol HealthChecking: Sendable {
    /// Comprueba la salud de la dependencia subyacente.
    ///
    /// - Parameter database: La base de datos contra la que comprobar la conectividad.
    /// - Returns: Un `HealthStatus` que describe el resultado de la comprobación.
    func check(on database: any Database) async -> HealthStatus
}

extension Application {
    private struct HealthCheckerKey: StorageKey {
        typealias Value = any HealthChecking
    }

    /// La implementación de `HealthChecking` usada por la ruta `/health`.
    ///
    /// Por defecto es `DatabaseHealthChecker` si nunca se establece otra. Los tests
    /// pueden sobreescribir este valor con una implementación stub para ejercitar la
    /// ruta sin una base de datos real.
    public var healthChecker: any HealthChecking {
        get {
            self.storage[HealthCheckerKey.self] ?? DatabaseHealthChecker()
        }
        set {
            self.storage[HealthCheckerKey.self] = newValue
        }
    }
}

/// Una implementación de `HealthChecking` que verifica la conectividad con Postgres
/// ejecutando una consulta trivial directamente contra la conexión configurada.
public struct DatabaseHealthChecker: HealthChecking {
    /// Crea un nuevo comprobador de salud de base de datos.
    public init() {}

    /// Ejecuta `SELECT 1` contra la base de datos dada para confirmar que la conexión
    /// está viva.
    ///
    /// - Parameter database: La base de datos contra la que comprobar la conectividad.
    /// - Returns: Un `HealthStatus` sano si la consulta tiene éxito, o uno no sano que
    ///   describe el fallo en caso contrario.
    public func check(on database: any Database) async -> HealthStatus {
        guard let postgres = database as? any PostgresDatabase else {
            return HealthStatus(isHealthy: false, message: "Configured database is not PostgreSQL.")
        }
        do {
            _ = try await postgres.simpleQuery("SELECT 1").get()
            return HealthStatus(isHealthy: true, message: "Database connection is healthy.")
        } catch {
            return HealthStatus(isHealthy: false, message: "Database connection failed: \(error)")
        }
    }
}

/// El resultado de una comprobación de salud, devuelto como cuerpo JSON de `GET /health`.
public struct HealthStatus: Content, Equatable, Sendable {
    /// Si la dependencia comprobada es alcanzable y funciona correctamente.
    public let isHealthy: Bool

    /// Una descripción legible por humanos del resultado de la comprobación.
    public let message: String

    /// Crea un nuevo estado de salud.
    ///
    /// - Parameters:
    ///   - isHealthy: Si la dependencia comprobada está sana.
    ///   - message: Una descripción legible por humanos del resultado.
    public init(isHealthy: Bool, message: String) {
        self.isHealthy = isHealthy
        self.message = message
    }
}
