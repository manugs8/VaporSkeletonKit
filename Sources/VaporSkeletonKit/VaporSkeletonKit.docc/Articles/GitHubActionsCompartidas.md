# GitHub Actions compartidas

Los tres workflows reutilizables y la composite action que este repo aloja además del
paquete Swift, y cómo un proyecto consumidor los conecta.

## Por qué viven aquí, y no en cada proyecto

Igual que el código Swift de este kit, el pipeline de CI/CD de un proyecto derivado de
`BackendSkeleton` es en gran parte idéntico de un proyecto a otro: build/test contra
Postgres, construir la imagen Docker de producción, un smoke test tras el despliegue, un
E2E completo contra esa imagen sobre una rama Neon efímera. Copiar esos ficheros
`.yml` a cada repo tiene el mismo problema que copiar `.swift`: una corrección hecha en
uno nunca llega a los demás.

Este repo resuelve eso exactamente igual que con el paquete SPM, pero con el mecanismo
propio de GitHub Actions: `on: workflow_call`. Un workflow con ese trigger no se ejecuta
nunca por sí mismo — ni aquí, ni en ningún push/PR de este repo — sino que otro
workflow lo *invoca* referenciándolo por path:

```yaml
jobs:
  ci:
    uses: manugs8/VaporSkeletonKit/.github/workflows/reusable-ci.yml@main
```

`actions/checkout` dentro de `reusable-ci.yml` sigue haciendo checkout del repositorio
**del que llama**, no de este — así es como funciona `workflow_call`, no algo que este
kit tenga que gestionar explícitamente.

## El pipeline completo

![Pipeline de CI/CD: el ci.yml del consumidor invoca reusable-ci.yml (con sus jobs unit-tests, integration-tests, docker-build y lint-openapi), y tras el merge a main, reusable-deploy-smoke.yml y opcionalmente reusable-e2e.yml.](pipeline-cicd)

### `reusable-ci.yml`

El job `resolve-swift-image` lee la línea `FROM <image> AS build` del propio
`Dockerfile` del consumidor, para que `unit-tests` e `integration-tests` corran sobre la
imagen Swift/OS **exacta** que usa producción — sin una segunda copia mantenida a mano
que pudiera divergir silenciosamente de lo que realmente se despliega. `unit-tests`
corre lógica pura (`swift test --filter AppUnitTests`); `integration-tests` añade un
contenedor de servicio `postgres:16` y corre con `AUTH_DISABLED=true`, ya que la
frontera de autenticación la cubre la propia suite de tests de `WorkOSBearerAuth`, no
este nivel. `docker-build` construye la imagen de producción sin publicarla, para que un
`Dockerfile` roto falle en CI en lugar de solo al desplegar. `lint-openapi` valida el
spec del proyecto con Redocly.

### `reusable-deploy-smoke.yml`

Consulta `GET /health` con backoff después de que la propia integración nativa de
Render con GitHub redespliegue al hacer push a `main` — este workflow no dispara el
despliegue, solo lo verifica, con una espera fija inicial (Render Free no ofrece un
webhook de "despliegue terminado" que consultar). Si el smoke test falla, no hay
rollback automático — Render Free tampoco tiene una API de rollback programable —, así
que el propio dashboard de Render es el camino para volver a desplegar el build anterior
bueno.

### `reusable-e2e.yml`

El más elaborado de los tres: levanta la imagen Docker de producción real, crea una rama
Neon efímera a partir de `e2e-base`, y arranca un túnel rápido de Cloudflare para dar al
falso Authorization Server (que sirve el JWKS de prueba) un endpoint HTTPS real y
públicamente confiable — sin ningún certificado que generar ni distribuir. La rama Neon
se destruye siempre al terminar, incluso si el test falla, para no acumular ramas contra
el límite del plan gratuito. Ver los propios comentarios del workflow para el resto de
la mecánica (limpieza de espacio en disco del runner, contenedor opcional de caída de
base de datos, etc.).

### `protected-paths-check` (composite action)

Distinta de los tres workflows anteriores: es una *composite action*, no un workflow —
un único paso reutilizable, no un pipeline de jobs completo —, pensada para insertarse
dentro de un job que ya hace otras cosas. Compara el diff de una PR contra el fichero
`.github/protected-paths.txt` del propio consumidor (un pathspec `:(glob)` de git por
línea) y, si la PR toca alguna ruta protegida, añade un resumen al job y una etiqueta
`protected-change` — sin bloquear el merge por sí sola. Un proyecto le da dientes reales
combinándola con branch protection que exija revisión de CODEOWNERS.

## Cómo lo conecta un proyecto consumidor

El propio `ci.yml` de `BackendSkeleton`, del que salen estos ficheros, es intencionadamente
delgado: solo conecta triggers, permisos y las dos llamadas.

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  ci:
    uses: manugs8/VaporSkeletonKit/.github/workflows/reusable-ci.yml@main

  protected-paths-check:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: manugs8/VaporSkeletonKit/.github/actions/protected-paths-check@main
```

`protected-paths-check` está en un job separado de `ci` porque necesita
`pull-requests: write` para poder etiquetar la PR — un permiso que el resto del pipeline
no necesita, y que conviene no concederle de más.

Referenciar por `@main` significa que una corrección hecha aquí llega a todos los
consumidores en su siguiente ejecución de CI, sin que ninguno tenga que tocar su propio
repositorio. Fijar a un tag concreto (`@v0.5.0`) es la alternativa cuando un proyecto
prefiere que ese mismo cambio requiera un opt-in explícito.

## Este repo se prueba a sí mismo igual que un consumidor

`VaporSkeletonKit` es también un paquete Swift real, con su propia suite de tests — así
que, además de alojar los workflows reutilizables, tiene su propio `ci.yml` (sin
`workflow_call`, disparado por su propio push/PR a `main`) que aplica exactamente el
mismo patrón que `integration-tests` de `reusable-ci.yml`: un contenedor de servicio
`postgres:16` con las mismas variables `DATABASE_*`, para que `HealthRouteTests` (ver
<doc:ComprobacionesDeSalud>) corra contra una base de datos real en cada push/PR.
