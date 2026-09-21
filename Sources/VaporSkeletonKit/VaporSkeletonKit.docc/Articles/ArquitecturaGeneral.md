# Arquitectura general

Dónde encaja `VaporSkeletonKit` entre tu proyecto, `WorkOSBearerAuth` y los productos de soporte para pruebas.

## Descripción general

`VaporSkeletonKit` parte de una premisa simple: todo lo que **no** es lógica de negocio
en un backend Vapor debería vivir en un único sitio, versionado, con sus propios tests,
en lugar de copiado y pegado en cada proyecto nuevo.

![Arquitectura general: el proyecto consumidor en la parte superior, con WorkOSBearerAuth, VaporSkeletonKit y los productos de soporte de tests debajo, y los tres productos SPM base de VaporSkeletonKit (más sus equivalentes MCP) en la base.](arquitectura-general)

Un proyecto consumidor solo escribe tres cosas: su `configure(_:)`, sus modelos/rutas de
dominio, y el wrapper delgado que conecta sus tests con `VaporSkeletonKitTesting`/
`VaporSkeletonKitE2ESupport`. Todo lo demás — arrancar la app, hablar con Postgres,
servir `/docs`, montar MCP, comprobar salud, y el soporte para pruebas locales — vive aquí.

## Seis productos SPM, con dependencias deliberadas entre sí

`Package.swift` declara seis `.library`, cada una con un propósito y un peso de
dependencias distinto — tres para la superficie base (Postgres, health, arranque) y
tres equivalentes para MCP, que dependen de las primeras en vez de duplicarlas:

| Producto | Se enlaza en | Depende de |
|---|---|---|
| `VaporSkeletonKit` | El target de la app, en producción | Vapor, Fluent, FluentPostgresDriver |
| `VaporSkeletonKitTesting` | El target de tests de integración | VaporSkeletonKit, VaporSkeletonKitE2ESupport, Vapor, Fluent, VaporTesting |
| `VaporSkeletonKitE2ESupport` | Targets de tests E2E / seed | Ningún framework de servidor |
| `VaporSkeletonKitMCP` | El target de la app, si exportas MCP | VaporSkeletonKit, Vapor, swift-sdk (MCP) |
| `VaporSkeletonKitMCPTesting` | Tests de integración de MCP | VaporSkeletonKitTesting, VaporSkeletonKitMCP, MCP, VaporTesting |
| `VaporSkeletonKitMCPE2ESupport`| Tests E2E de MCP | VaporSkeletonKitE2ESupport, MCP |

Que sean múltiples productos y no uno solo importa: `VaporSkeletonKitTesting` nunca se enlaza
en producción (evita que herramientas de test lleguen a un binario que se despliega), y
`VaporSkeletonKitE2ESupport` deliberadamente no depende de Vapor — una suite E2E habla
HTTP real contra un servidor que ya está corriendo (en un proceso en local o CI), así que no tiene ningún motivo para enlazar la pila
completa del servidor. El mismo split que usa `WorkOSBearerAuth` para su propio
`WorkOSBearerAuthTesting`.

Para el detalle de qué aporta cada nivel de testing, ver <doc:TestingYE2E>.

## La relación con `WorkOSBearerAuth`

`VaporSkeletonKit` no sabe nada de autenticación, y `WorkOSBearerAuth` no sabe nada de
Postgres, MCP ni OpenAPI. Ambos paquetes se enlazan juntos en el mismo `configure(_:)`,
en el orden que decida el proyecto consumidor, y comparten un patrón de diseño
deliberado: **ninguno de los dos lee `Environment` por sí mismo.**

```swift
// El propio configure(_:) del proyecto consumidor
func configure(_ app: Application) throws {
    try configureBearerAuth(app, environment: BearerAuthEnvironmentConfig(
        authDisabled: Environment.get("AUTH_DISABLED").flatMap(Bool.init) == true,
        workOSIssuer: Environment.get("WORKOS_ISSUER"),
        workOSResourceIndicatorsRaw: Environment.get("WORKOS_RESOURCE_INDICATORS")
    ))

    app.databases.use(
        try makePostgresConfiguration(from: PostgresEnvironmentConfig(
            databaseURL: Environment.get("DATABASE_URL"),
            // ...
        )),
        as: .psql
    )

    try mountMCPServer(app, name: "MyProject", version: "1.0.0", instructions: "...", tools: [...])
}
```

Esto significa que ninguno de los dos paquetes asume un nombre concreto de variable de
entorno — el proyecto consumidor decide cómo se llaman sus propias variables y en qué
orden las lee, y ambos tipos de configuración (`BearerAuthEnvironmentConfig`,
`PostgresEnvironmentConfig`) se pueden construir directamente en un test sin mutar el
entorno real del proceso.

Cuando `mountMCPServer` se llama, da por hecho que la autenticación ya está adjunta a
`app` — así REST y MCP comparten exactamente la misma comprobación de auth en lugar de
que el servidor MCP reimplemente la suya. Ver <doc:ServidorMCP> para el porqué de esa
decisión.

## Qué NO hace este kit

Deliberadamente, `VaporSkeletonKit` no incluye:

- **Modelos ni migraciones de dominio.** Eso es responsabilidad exclusiva del proyecto
  consumidor.
- **Autenticación.** Vive en `WorkOSBearerAuth`.
- **Generación de tipos desde el spec OpenAPI.** El kit sirve el fichero YAML crudo
  (<doc:DocumentacionOpenAPI>), pero no genera código — eso lo hace
  `swift-openapi-generator` sobre el propio spec del proyecto.

Si una pieza nueva es realmente genérica y libre de lógica de negocio, tiene sentido
aquí. Si depende del dominio de un proyecto concreto, no.
