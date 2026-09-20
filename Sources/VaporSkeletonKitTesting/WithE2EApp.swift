import Fluent
import Vapor
import VaporSkeletonKitE2ESupport
import Foundation

/// Levanta dinámicamente un nodo del servidor en un puerto aleatorio libre del SO,
/// aplicándole la configuración y exponiendo los endpoints Backdoor (E2E).
/// Permite un teardown seguro y asíncrono para deshacer migraciones y apagar el servidor,
/// aislando por completo cada test para su ejecución paralela (Testing Framework).
///
/// Este método arranca un NIO Server real (`app.server.start()`), lo que permite que 
/// un `E2EHTTPClient` emita peticiones de red TCP puras simulando un entorno productivo.
public func withE2EServer(
    environment: [String: String] = [:],
    configure: (Application) async throws -> Void,
    test: (E2EHTTPClient) async throws -> Void
) async throws {
    // 1. Forzamos modo E2E (Enciende middlewares y rutas _test/fault) y seteamos variables externas
    setenv("E2E_MODE", "true", 1)
    for (key, value) in environment {
        setenv(key, value, 1)
    }
    
    let app = try await Application.make(.testing)
    do {
        // Enlaza la configuración del proyecto consumidor a esta instancia
        try await configure(app)
        
        // 2. Limpieza de base de datos y lanzamiento de migraciones aisladas
        try? await app.autoRevert()
        try await app.autoMigrate()
        
        // 3. Asignar puerto libre aleatorio y levantar el NIO Server a nivel OS
        app.http.server.configuration.port = 0
        try await app.asyncBoot()
        try app.server.start()
        
        guard let localAddress = app.http.server.shared.localAddress,
              let port = localAddress.port else {
            fatalError("No se ha podido obtener el puerto dinámico asignado localmente en withE2EServer")
        }
        
        // Creamos el cliente E2E apuntando directamente al puerto cedido por macOS al NIO server
        let client = E2EHTTPClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        
        // 4. Se ejecuta el bloque del Test (E2EHTTPClient) inyectado de manera segura
        try await test(client)
        
        // 5. Destrucción Asíncrona Garantizada: Se destruyen tablas y recursos NIO
        try? await app.autoRevert()
        await app.server.shutdown()
    } catch {
        // Si hay fallo o assert en el test -> Garantizamos también la limpieza de entorno
        try? await app.autoRevert()
        await app.server.shutdown()
        try? await app.asyncShutdown()
        throw error
    }
    
    try await app.asyncShutdown()
}
