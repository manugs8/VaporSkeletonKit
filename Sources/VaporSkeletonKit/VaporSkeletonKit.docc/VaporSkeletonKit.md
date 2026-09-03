# ``VaporSkeletonKit``

Infraestructura genérica y libre de lógica de negocio para backends Vapor 4 + Fluent +
PostgreSQL, para que un proyecto solo tenga que escribir su propio dominio.

## Descripción general

Cada backend que arrancas desde cero repite el mismo código de infraestructura: arrancar
la `Application`, configurar Postgres contra Neon, servir la documentación OpenAPI,
montar un servidor MCP para que un agente pueda inspeccionar la app, exponer un
`/health`... Nada de eso es específico de un proyecto — y copiarlo de un repo a otro
significa que una corrección hecha en uno nunca llega a los demás.

`VaporSkeletonKit` extrae exactamente esa infraestructura a un paquete SPM, más un
conjunto de GitHub Actions reutilizables para el pipeline de CI/CD. Un proyecto
consumidor la enlaza, implementa `configure(_:)` con su propio dominio, y hereda gratis
todo lo que este kit resuelve — ver el esquema de conjunto en
<doc:ArquitecturaGeneral>.

`WorkOSBearerAuth` es el paquete complementario: cubre la autenticación bearer contra
WorkOS AuthKit. `VaporSkeletonKit` da por hecho que la autenticación (si la hay) ya está
adjunta a la `Application` antes de que sus funciones se llamen, y nunca la reimplementa.

## Cómo empezar

Si es la primera vez que usas este kit, sigue <doc:Tutoriales> — dos tutoriales guiados
que montan un backend desde `Package.swift` en blanco hasta un servidor con Postgres,
`/health` y una herramienta MCP propia funcionando.

Si ya conoces el kit y buscas el porqué de una pieza concreta, ve directo al artículo
correspondiente.

## Topics

### Arquitectura y diseño

- <doc:ArquitecturaGeneral>
- <doc:ArranqueDeLaApp>
- <doc:ServidorMCP>
- <doc:ComprobacionesDeSalud>

### Datos y documentación

- <doc:ConfiguracionPostgres>
- <doc:DocumentacionOpenAPI>

### Testing y CI/CD

- <doc:TestingYE2E>
- <doc:GitHubActionsCompartidas>

### Guías paso a paso

- <doc:Tutoriales>
