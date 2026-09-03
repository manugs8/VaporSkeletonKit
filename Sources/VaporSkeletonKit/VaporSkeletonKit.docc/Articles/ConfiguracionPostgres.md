# Configuración de Postgres

Los dos caminos que admite ``makePostgresConfiguration(from:)`` — `DATABASE_URL` de Neon
frente a host/puerto/usuario discretos — y por qué el TLS se trata distinto en cada uno.

## Dos estilos de configuración, un único punto de entrada

`PostgresEnvironmentConfig` no representa "la" forma de configurar Postgres, sino dos
formas distintas que conviven en el mismo tipo:

1. **`databaseURL`** — una única cadena de conexión, el formato que entrega Neon
   directamente. Es el camino de producción.
2. **Campos discretos** (`host`, `port`, `username`, `password`, `database`) — usados
   cuando `databaseURL` es `nil`. Es el camino de desarrollo local, contra un Postgres
   en `localhost`.

`makePostgresConfiguration(from:)` decide cuál de los dos usar mirando simplemente si
`databaseURL` está presente:

```swift
public func makePostgresConfiguration(from config: PostgresEnvironmentConfig) throws -> DatabaseConfigurationFactory {
    if let databaseURL = config.databaseURL {
        var sqlConfiguration = try SQLPostgresConfiguration(url: databaseURL)
        sqlConfiguration.coreConfiguration.tls = .require(try makeNIOSSLContext())
        return .postgres(configuration: sqlConfiguration)
    }

    guard let host = config.host, let username = config.username,
          let password = config.password, let database = config.database
    else {
        throw PostgresConfigurationError.missingDatabaseEnvironment
    }
    // ...
}
```

Si ninguno de los dos caminos tiene la información completa, la función lanza
`PostgresConfigurationError.missingDatabaseEnvironment` en lugar de intentar adivinar —
un fallo explícito y temprano en `configure(_:)`, capturado por
``runApp(configure:)`` (ver <doc:ArranqueDeLaApp>), es preferible a un `nil` silencioso
que solo se manifiesta más tarde como un error de conexión confuso.

## TLS: obligatorio en producción, opcional en local

Neon exige TLS en cada conexión, así que el camino `databaseURL` **siempre** establece
`.require`, sin ninguna opción para desactivarlo. El camino de campos discretos, pensado
para desarrollo local contra un Postgres sin TLS configurado, respeta en cambio
`tlsDisabled`:

```swift
let tls: PostgresConnection.Configuration.TLS = config.tlsDisabled
    ? .disable
    : .require(try makeNIOSSLContext())
```

Cuando TLS está activo, el contexto se construye deliberadamente permisivo
(`certificateVerification = .none`):

```swift
private func makeNIOSSLContext() throws -> NIOSSLContext {
    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.certificateVerification = .none
    return try NIOSSLContext(configuration: tlsConfiguration)
}
```

Esto es correcto para el caso que cubre este kit — un proveedor gestionado como Neon,
cuyo certificado está firmado por una CA pública pero al que se accede sin pinning —, no
un descuido. Verificar el certificado exigiría distribuir o gestionar el CA bundle de
Neon, sin aportar protección real frente al escenario que de verdad importa (un
atacante en la red entre la app y Neon), ya que la conexión sigue yendo cifrada por TLS
en todo momento.

## El mismo patrón que `WorkOSBearerAuth`

`PostgresEnvironmentConfig` nunca lee `Environment` por sí mismo — es el proyecto
consumidor quien lee sus propias variables de entorno (con los nombres que prefiera) y
pasa los valores ya resueltos:

```swift
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

Es el mismo patrón que sigue `configureBearerAuth` de `WorkOSBearerAuth` para
`BearerAuthEnvironmentConfig` — y no es casualidad: mantiene ambos paquetes agnósticos
de cómo un proyecto concreto nombra sus variables, y permite testear la lógica de
configuración construyendo el tipo directamente, sin mutar variables de entorno reales
del proceso. Los tests de `PostgresConfigurationTests` en este mismo repo hacen
justamente eso.
