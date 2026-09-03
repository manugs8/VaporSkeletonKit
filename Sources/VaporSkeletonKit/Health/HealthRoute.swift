import Vapor

/// Registra `GET /health`, respaldada por `app.healthChecker` (``HealthChecking``).
///
/// Escrita a mano deliberadamente en lugar de generada a partir de un spec OpenAPI, a
/// diferencia del resto de la superficie de API de un proyecto consumidor: `/health` es
/// un endpoint de operaciones (consultado por Render, por `reusable-deploy-smoke.yml` y
/// por las suites E2E que verifican el comportamiento ante una caída de la base de
/// datos), no forma parte de la API de negocio contra la que integra un cliente, y que
/// todos los consumidores compartan exactamente la misma ruta/respuesta garantiza que
/// nunca puedan divergir como sí podrían hacerlo tipos generados por proyecto. No
/// aparecerá en el propio `/docs`/`openapi.yaml` de un proyecto consumidor —
/// documéntala ahí como un añadido fijo si un proyecto quiere que aparezca listada.
///
/// - Parameter app: La `Application` sobre la que registrar la ruta.
public func registerHealthRoute(_ app: Application) {
    app.get("health") { req async throws -> Response in
        let status = await req.application.healthChecker.check(on: req.db)
        let response = Response(status: status.isHealthy ? .ok : .serviceUnavailable)
        try response.content.encode(status)
        return response
    }
}
