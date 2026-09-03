# Documentación OpenAPI

Qué hace ``registerOpenAPIDocs(_:specFilePath:docsTitle:)`` — y qué es responsabilidad
del proyecto consumidor, no de este kit.

## Dos rutas, un único spec como fuente de verdad

`registerOpenAPIDocs(_:specFilePath:docsTitle:)` registra dos rutas a partir de un único
fichero YAML que ya existe en el proyecto consumidor:

- `GET /openapi.yaml` — sirve el fichero en crudo, tal cual está en disco. Útil para
  importar el spec en Postman o cualquier otra herramienta compatible con OpenAPI.
- `GET /docs` — una página [Swagger UI](https://swagger.io/tools/swagger-ui/)
  autocontenida, cargada desde un CDN público, que apunta a `/openapi.yaml`. Permite
  explorar la API desde un navegador sin instalar nada.

```swift
registerOpenAPIDocs(app, specFilePath: "Sources/App/openapi.yaml", docsTitle: "MyProject API Docs")
```

## Por qué la ruta es relativa al directorio de trabajo

`specFilePath` se resuelve como `app.directory.workingDirectory + specFilePath`, no
como una ruta absoluta ni como un recurso embebido en el binario. Esto es intencional:
la misma llamada, con la misma ruta relativa, funciona tanto en desarrollo local
(`swift run` desde la raíz del repo) como dentro de la imagen Docker de producción — con
la única condición de que el `Dockerfile` copie el fichero YAML a esa misma ruta
relativa dentro de la imagen. Si el fichero no existe en esa ruta, la petición a
`/openapi.yaml` responde `404` en lugar de fallar de forma más oscura.

## Lo que este kit no hace: generar código

`VaporSkeletonKit` sirve el spec — no lo genera, ni genera tipos Swift a partir de él.
Eso es trabajo de [`swift-openapi-generator`](https://github.com/apple/swift-openapi-generator),
ejecutado por el propio proyecto consumidor sobre su propio spec. La razón de esa
frontera es la misma que la del resto del kit: el contenido del spec OpenAPI es la API
de negocio del proyecto — depende enteramente de su dominio —, así que no tiene cabida
aquí. Lo único genérico es *cómo se sirve* ese spec una vez escrito, y eso es lo que
`registerOpenAPIDocs` resuelve.

`reusable-ci.yml` (ver <doc:GitHubActionsCompartidas>) sí valida el spec en CI, con un
job `lint-openapi` que ejecuta Redocly contra `Sources/App/openapi.yaml` — pero
validar el YAML no es lo mismo que generarlo ni servirlo, y ese job vive en el pipeline
de CI, no en este target.
