# VaporSkeletonKit

Generic, business-logic-free infrastructure shared by backends built from
[`BackendSkeleton`](https://github.com/manugs8/BackendSkeleton) — a Vapor 4 + Fluent +
PostgreSQL template deployed on Render against Neon. Extracted so that a project derived
from that template depends on this package via SPM instead of copying `.swift` files
that then drift out of sync with fixes made here.

Companion package: [`WorkOSBearerAuth`](https://github.com/manugs8/WorkOSBearerAuth)
covers authentication; this package covers everything else that isn't authentication and
isn't business logic.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Postgres configuration](#postgres-configuration)
- [OpenAPI / Swagger UI serving](#openapi--swagger-ui-serving)
- [MCP server mounting](#mcp-server-mounting)
- [Testing](#testing)

## Requirements

- Swift 6 (strict concurrency, `swiftLanguageModes: [.v6]`)
- macOS 13+ / Linux
- Vapor 4.115+

## Installation

```swift
.package(url: "https://github.com/manugs8/VaporSkeletonKit.git", from: "0.1.0")
```

Add `"VaporSkeletonKit"` as a dependency of the target that calls `configure(_:)` on
your `Application`.

## Postgres configuration

`makePostgresConfiguration(from:)` builds a `DatabaseConfigurationFactory` from a
`PostgresEnvironmentConfig` — either a single `DATABASE_URL` (Neon's format, always TLS)
or discrete host/port/username/password/database values (local development, TLS
optional). It never reads `Environment` itself — your app reads its own environment
variables (however it names them) and passes the values in, same pattern as
`WorkOSBearerAuth`'s `configureBearerAuth`:

```swift
import VaporSkeletonKit

app.databases.use(
    try makePostgresConfiguration(from: PostgresEnvironmentConfig(
        databaseURL: Environment.get("DATABASE_URL"),
        host: Environment.get("DATABASE_HOST"),
        port: Environment.get("DATABASE_PORT").flatMap(Int.init),
        username: Environment.get("DATABASE_USERNAME"),
        password: Environment.get("DATABASE_PASSWORD"),
        database: Environment.get("DATABASE_NAME"),
        tlsDisabled: Environment.get("DATABASE_TLS") == "disable"
    )),
    as: .psql
)
```

TLS is established with a permissive `NIOSSLContext` (certificate verification off,
public-CA signed) suitable for managed providers like Neon reached without pinning.

## OpenAPI / Swagger UI serving

`registerOpenAPIDocs(_:specFilePath:docsTitle:)` registers `GET /openapi.yaml` (streams
the raw spec file) and `GET /docs` (a Swagger UI page loaded from a public CDN, pointing
at it):

```swift
import VaporSkeletonKit

registerOpenAPIDocs(app, specFilePath: "Sources/App/openapi.yaml", docsTitle: "MyProject API Docs")
```

`specFilePath` is resolved relative to `app.directory.workingDirectory`, so the same
call works in local development and inside the production Docker image as long as the
YAML file is copied to that same relative path (see `BackendSkeleton`'s `Dockerfile`).

## MCP server mounting

`mountMCPServer(_:name:version:instructions:tools:resources:path:)` mounts a stateless
[MCP](https://modelcontextprotocol.io) server at `POST/GET/DELETE /mcp` (or another
`path`), bridging Vapor's HTTP types to the MCP SDK's transport. A fresh `MCP.Server` is
built per request — the SDK's stateless mode rejects a second `initialize` on an
already-initialized server and carries no session id to tell independent clients apart.

```swift
import VaporSkeletonKit

try mountMCPServer(
    app,
    name: "MyProject",
    version: "1.0.0",
    instructions: "Tools for inspecting and managing MyProject.",
    tools: [GetHealthTool(app: app), ListItemsTool(app: app)],
    resources: [ItemsResource(app: app)]
)
```

Implement `MCPTool`/`MCPResource` for your own domain types — neither protocol nor the
mounting/dispatch code knows anything about a specific business model. Authentication is
expected to already be attached to `app` (e.g. via `WorkOSBearerAuth`) before this is
called, so REST and MCP share the same check instead of MCP re-implementing its own.

Throw `MCPToolError` from a tool's `call(arguments:)` for any failure the calling model
can reasonably see and react to (`invalidArgument`, `notFound`, `database`,
`internalError`) — these are reported as a tool result with `isError: true`, not a
transport-level failure.

## Testing

```bash
swift test
```
