import Fluent
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitE2ESupport
import SQLKit
import Foundation

/// Levanta dinámicamente un nodo del servidor en un puerto aleatorio libre del SO,
/// aprovisionando una Base de Datos en Postgres temporal 100% aislada para este test y
/// exponiendo los endpoints Backdoor (E2E). Permite un teardown seguro y asíncrono.
///
/// Este método soluciona el problema de la concurrencia delegando en el Closure el 
/// nombre de la base de datos recién generada (`dynamicDB`), que el consumidor debe usar 
/// en su propia configuración de test.
public func withE2EServer(
    configure: (Application, _ dynamicDB: String) async throws -> Void,
    test: (E2EHTTPClient) async throws -> Void
) async throws {
    // 1. Configuramos credenciales máster
    let masterConfig = PostgresEnvironmentConfig(
        databaseURL: Environment.get("DATABASE_URL"),
        host: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
        username: Environment.get("DATABASE_USERNAME") ?? "postgres",
        password: Environment.get("DATABASE_PASSWORD") ?? "postgres",
        database: Environment.get("DATABASE_NAME") ?? "postgres",
        tlsDisabled: Environment.get("DATABASE_TLS") != "require"
    )
    
    // 2. Extraemos la creación de la BD dinámica
    let dynamicDBName = try await createE2EDatabase(masterConfig: masterConfig)
    
    // 3. Levantamos NUESTRO SERVER pasándole explícitamente el dynamicDBName
    let e2eApp = try await Application.make(.testing)
    
    // A partir de aquí necesitamos asegurar el DROP de la base de datos generada
    do {
        try await configure(e2eApp, dynamicDBName)
        
        try? await e2eApp.autoRevert()
        try await e2eApp.autoMigrate()
        
        e2eApp.http.server.configuration.port = 0
        try await e2eApp.asyncBoot()
        try e2eApp.server.start()
        
        guard let localAddress = e2eApp.http.server.shared.localAddress,
              let serverPort = localAddress.port else {
            fatalError("No se ha podido obtener el puerto dinámico asignado localmente en withE2EServer")
        }
        
        let client = E2EHTTPClient(baseURL: URL(string: "http://127.0.0.1:\(serverPort)")!)
        
        // Ejecutamos Test inyectado
        try await test(client)
        
        try? await e2eApp.autoRevert()
        await e2eApp.server.shutdown()
    } catch {
        // Cleanup ante fallo
        try? await e2eApp.autoRevert()
        await e2eApp.server.shutdown()
        try? await e2eApp.asyncShutdown()
        try? await dropE2EDatabase(dynamicDBName, masterConfig: masterConfig)
        throw error
    }
    
    // 4. Terminar instancia server
    try await e2eApp.asyncShutdown()
    
    // 5. Destrucción Garantizada de la BD temporal E2E
    try await dropE2EDatabase(dynamicDBName, masterConfig: masterConfig)
}

private func createE2EDatabase(masterConfig: PostgresEnvironmentConfig) async throws -> String {
    let dynamicDBName = "e2e_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let adminApp = try await Application.make(.testing)
    adminApp.databases.use(try makePostgresConfiguration(from: masterConfig), as: .psql)
    
    if let sql = adminApp.db as? any SQLDatabase {
        try await sql.raw("CREATE DATABASE \"\(unsafeRaw: dynamicDBName)\"").run()
    } else {
        adminApp.logger.warning("No se pudo resolver adminApp.db como SQLDatabase para crear la BD E2E dinámica.")
    }
    try await adminApp.asyncShutdown()
    
    return dynamicDBName
}

private func dropE2EDatabase(_ name: String, masterConfig: PostgresEnvironmentConfig) async throws {
    let adminApp = try await Application.make(.testing)
    adminApp.databases.use(try makePostgresConfiguration(from: masterConfig), as: .psql)
    
    if let sql = adminApp.db as? any SQLDatabase {
        // En PostgreSQL a veces hay conexiones pendientes, por lo que forzamos desconexiones antes de hacer drop:
        try? await sql.raw("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '\(unsafeRaw: name)'").run()
        try await sql.raw("DROP DATABASE \"\(unsafeRaw: name)\"").run()
    }
    try await adminApp.asyncShutdown()
}
