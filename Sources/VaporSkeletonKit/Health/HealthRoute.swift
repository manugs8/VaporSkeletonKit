import Vapor

/// Registers `GET /health`, backed by `app.healthChecker` (``HealthChecking``).
///
/// Deliberately hand-written rather than generated from an OpenAPI spec, unlike the
/// rest of a consuming project's API surface: `/health` is an ops endpoint (polled by
/// Render, by `reusable-deploy-smoke.yml`, and by E2E suites asserting DB-outage
/// behavior), not part of the business API a client integrates against, and every
/// consumer sharing this exact route/response guarantees they can never drift the way
/// per-project generated types could. It won't show up in a consuming project's own
/// `/docs`/`openapi.yaml` — document it there as a fixed addendum instead if a project
/// wants it listed.
///
/// - Parameter app: The `Application` to register the route on.
public func registerHealthRoute(_ app: Application) {
    app.get("health") { req async throws -> Response in
        let status = await req.application.healthChecker.check(on: req.db)
        let response = Response(status: status.isHealthy ? .ok : .serviceUnavailable)
        try response.content.encode(status)
        return response
    }
}
