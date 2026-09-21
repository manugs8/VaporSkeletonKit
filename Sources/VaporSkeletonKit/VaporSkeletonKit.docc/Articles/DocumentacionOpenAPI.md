# Documentación OpenAPI

Qué hace ``registerOpenAPIDocs(_:specData:docsTitle:)`` — y qué es responsabilidad
del proyecto consumidor, no de este kit.

## Dos rutas, un único spec como fuente de verdad

`registerOpenAPIDocs(_:specData:docsTitle:)` registra dos rutas a partir de los datos pasados:

- `GET /openapi.yaml` — sirve los datos (usualmente el fichero OpenAPI en crudo) como `application/yaml`. Útil para
  importar el spec en Postman o cualquier otra herramienta compatible con OpenAPI.
- `GET /docs` — una página [Swagger UI](https://swagger.io/tools/swagger-ui/)
  autocontenida, cargada desde un CDN público, que apunta a `/openapi.yaml`. Permite
  explorar la API desde un navegador sin instalar nada.

```swift
// Ejemplo usando openapi.yaml inyectado como Data desde un paquete externo
registerOpenAPIDocs(app, specData: openapiData, docsTitle: "MyProject API Docs")
```

## Por qué exponemos el spec como Data

El spec se suele encapsular en paquetes externos al proyecto (o bundles de recursos) y se expone como `Data`.
De esta forma, en vez de depender de rutas de disco duro o directorios de trabajo (que pueden fallar si no 
están configurados correctamente en Docker o en producción), el proyecto consumidor debe pasar explícitamente 
los datos del documento OpenAPI a esta función.

## Swagger UI: versión fijada y verificada por hash (SRI)

La página `GET /docs` carga Swagger UI desde unpkg con una versión exacta
(`swagger-ui-dist@5.33.0`, no un rango como `@5`) y con un atributo `integrity`
(SHA-384) en el `<link>` del CSS y en el `<script>` del bundle JS. Sin esto, un cambio
de contenido en esa versión del CDN — deliberado o por un CDN comprometido — se
ejecutaría en el navegador de quien visite `/docs` sin ningún aviso; con `integrity`,
el navegador se niega a aplicar/ejecutar el recurso si su hash no coincide.

Para actualizar la versión fijada:

```bash
curl -sL -o swagger-ui.css "https://unpkg.com/swagger-ui-dist@<version>/swagger-ui.css"
curl -sL -o swagger-ui-bundle.js "https://unpkg.com/swagger-ui-dist@<version>/swagger-ui-bundle.js"
openssl dgst -sha384 -binary swagger-ui.css | openssl base64 -A
openssl dgst -sha384 -binary swagger-ui-bundle.js | openssl base64 -A
```

y sustituir `swaggerUIDistVersion`, `swaggerUICSSIntegrity` y
`swaggerUIBundleJSIntegrity` en `OpenAPIDocsRoutes.swift` por los nuevos valores —
nunca solo el número de versión sin recalcular los hashes.

## `docsTitle` se escapa como HTML

`docsTitle` se interpola dentro del `<title>` de la página Swagger UI. Aunque en la
práctica suele ser un literal fijo (`"MyProject API Docs"`), `registerOpenAPIDocs`
lo trata como contenido no confiable y escapa `&`, `<`, `>` y comillas antes de
interpolarlo — así, si algún día un proyecto consumidor lo deriva de configuración
externa en vez de un literal, un valor con `<script>` u otro markup no puede alterar
la estructura de la página ni inyectar JavaScript en ella.

## Lo que este kit no hace: generar código

`VaporSkeletonKit` sirve el spec — no lo genera, ni genera tipos Swift a partir de él.
Eso es trabajo de [`swift-openapi-generator`](https://github.com/apple/swift-openapi-generator),
ejecutado por el propio proyecto consumidor sobre su propio spec. La razón de esa
frontera es la misma que la del resto del kit: el contenido del spec OpenAPI es la API
de negocio del proyecto — depende enteramente de su dominio —, así que no tiene cabida
aquí. Lo único genérico es *cómo se sirve* ese spec una vez escrito, y eso es lo que
`registerOpenAPIDocs` resuelve.
