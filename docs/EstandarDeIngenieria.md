# Estándar de Ingeniería Backend

## Vapor + Fluent + PostgreSQL/Neon + Render + WorkOS + MCP

> **Estado:** Borrador v0.2 — mayoría de las cuestiones abiertas de origen (§24) ya
> resueltas por `VaporSkeletonKit`/`WorkOSBearerAuth`; quedan por decidir las marcadas
> como tal.
> **Propósito:** Estándar reutilizable de arquitectura e ingeniería para proyectos
> backend desarrollados conjuntamente por un desarrollador humano y agentes de
> programación basados en IA.

Este documento define la **norma**: qué debe cumplir un backend de este stack y por qué.
No documenta cómo `VaporSkeletonKit` o `WorkOSBearerAuth` la implementan — para eso está
el [catálogo DocC](../Sources/VaporSkeletonKit/VaporSkeletonKit.docc/VaporSkeletonKit.md)
de este paquete y el de `WorkOSBearerAuth`; cada sección que solapa con un artículo
concreto enlaza a él en vez de repetir su contenido.

---

# 1. Propósito

Este documento define una base reutilizable para proyectos backend construidos alrededor
de:

* Swift / Vapor
* Fluent
* PostgreSQL
* Neon
* Docker
* Render
* WorkOS
* MCP
* OpenAPI
* Pruebas Locales (TestSupport)
* Desarrollo asistido por IA

El objetivo no es imponer una aplicación concreta ni un modelo de dominio determinado.

Define los principios, la arquitectura, la estrategia de pruebas, el modelo de
despliegue y las protecciones del repositorio que deberían reutilizarse entre proyectos.

Los detalles específicos de cada proyecto deben pertenecer a un documento de
implementación independiente.

---

# 2. Principios fundamentales

## 2.1 Los tests E2E son un contrato funcional

Los tests E2E no son simplemente tests de implementación.

Protegen el comportamiento observable externamente del producto:

* códigos de estado HTTP;
* requisitos de autenticación;
* esquemas de respuesta;
* reglas de negocio importantes;
* comportamiento de persistencia;
* contratos REST;
* contratos de herramientas MCP.

Una suite E2E que pasa debe proporcionar evidencia significativa de que la aplicación
desplegada continúa comportándose de acuerdo con su contrato documentado.

---

## 2.2 Utilizar un entorno realista

Las pruebas E2E deben reproducir la arquitectura de producción de manera razonable.

Ruta preferida:

```
Cliente HTTP/MCP → Proceso del Servidor Vapor → middleware → capa de aplicación → Fluent → PostgreSQL / Neon
```

Debe evitarse crear una compilación específica para E2E que se comporte de forma diferente a producción, usando en su lugar variables de entorno que apunten a los servicios locales o mockeados que sean necesarios.

---

## 2.3 Las bases de datos E2E son efímeras

Cada ejecución E2E debe utilizar una base de datos PostgreSQL aislada.

Con Neon, el modelo preferido es: rama base estable → rama creada para una ejecución E2E
→ migraciones → seed determinista → tests E2E → eliminación de la rama.

No se debe compartir estado mutable entre ejecuciones E2E concurrentes.

No se debe depender de limpiar o restablecer el estado cuando sea viable destruir y
volver a crear la base de datos.

---

## 2.4 El contrato debe ser independiente de la implementación

La especificación de la API/herramienta describe qué debe hacer el sistema.

La implementación describe cómo lo hace.

Los tests verifican que la implementación satisface el contrato.

Una dirección de dependencias adecuada es: Contrato → Plan de pruebas → Implementación.

Nunca se debe derivar el contrato del comportamiento que casualmente exista en la
implementación actual.

---

# 3. Arquitectura

```
Clientes → REST API / Servidor MCP → Autenticación WorkOS → Vapor
    (middleware, handlers, services, MCP tools) → Fluent → PostgreSQL / Neon
```

Alrededor de la aplicación: Desarrollo en local → TestSupport (Pruebas Locales) → Despliegue a producción.

El diagrama completo de piezas, y de qué resuelve cada paquete compartido
(`VaporSkeletonKit` vs `WorkOSBearerAuth`), está en el artículo
[Arquitectura general](../Sources/VaporSkeletonKit/VaporSkeletonKit.docc/Articles/ArquitecturaGeneral.md)
del catálogo DocC de este repo.

---

# 4. Arquitectura de la aplicación

## 4.1 API REST

Los endpoints REST deben disponer de:

* contratos OpenAPI explícitos;
* modelos tipados de request/response;
* autenticación definida explícitamente;
* comportamiento de negocio determinista;
* comportamiento de errores documentado;
* un plan de pruebas.

Los handlers deben mantenerse delgados. La lógica de negocio debería residir
preferentemente en servicios de aplicación/dominio reutilizables, en lugar de
duplicarse en los handlers HTTP.

Cómo se sirve el spec y la UI de exploración (`/openapi.yaml`, `/docs`) está en
[Documentación OpenAPI](../Sources/VaporSkeletonKit/VaporSkeletonKit.docc/Articles/DocumentacionOpenAPI.md).

---

## 4.2 Autenticación mediante WorkOS

La autenticación constituye un límite de seguridad alrededor de la aplicación.

Flujo preferido: petición HTTP → middleware Bearer JWT → validación del token →
petición autenticada → lógica de aplicación.

Los handlers no deberían analizar ni validar los tokens de autenticación de forma
independiente. Los fallos de autenticación deben gestionarse antes de ejecutar la
lógica de negocio. La capa de aplicación no debería depender innecesariamente del
análisis específico de tokens de WorkOS.

### Entorno de pruebas

Un entorno de pruebas puede desactivar la autenticación externa cuando sea apropiado
para tests unitarios/de integración. Este comportamiento debe ser explícito.

En E2E, la autenticación debería probarse atravesando el límite real de autenticación
siempre que la infraestructura lo permita.

### Dos lecciones ya resueltas por `WorkOSBearerAuth`

Dos fallos concretos que motivaron parte de este principio ya están documentados y
resueltos en `WorkOSBearerAuth`, no hace falta repetirlos aquí en detalle:

* **No mezclar la verificación del token con la ejecución del handler en el mismo
  `try`/`catch`** — si no se separan, un error del handler no relacionado con
  autenticación puede camuflarse como 401 en vez de propagar su código real (p. ej.
  500). Ver el artículo
  [Flujo de una petición](https://github.com/manugs8/WorkOSBearerAuth/blob/main/Sources/WorkOSBearerAuth/WorkOSBearerAuth.docc/06-FlujoDeUnaPeticion.md).
* **Autorización de prueba automatizada en E2E sin un token real de larga duración** —
  sustituir la Authorization Server por una bajo control del propio pipeline (par de
  claves de prueba fijo, publicado como JWKS estático), para que el código de
  verificación no cambie, solo el emisor al que apunta. Ver la
  [Guía E2E](https://github.com/manugs8/WorkOSBearerAuth/blob/main/Sources/WorkOSBearerAuthTesting/WorkOSBearerAuthTesting.docc/GuiaE2E.md)
  de `WorkOSBearerAuthTesting`.

---

## 4.3 MCP

MCP se considera una interfaz de aplicación de primer nivel junto con REST.

Una herramienta MCP debe disponer de:

* esquema de entrada;
* esquema de salida;
* requisito de autenticación;
* requisito de autorización, cuando corresponda;
* comportamiento documentado;
* errores documentados;
* escenarios de prueba.

Cuando un endpoint REST y una herramienta MCP exponen la misma operación de negocio,
deberían compartir preferentemente la misma lógica de aplicación/dominio (servicio de
aplicación común a ambos adaptadores). Debe evitarse duplicar la misma consulta o regla
de negocio de forma independiente en REST y en MCP — pueden tener contratos externos
distintos, pero el comportamiento de negocio subyacente debería tener una única
implementación autoritativa siempre que resulte práctico.

El puente genérico Vapor↔MCP (por qué un `MCP.Server` nuevo por petición, cómo llega un
error de herramienta al modelo) está en
[Servidor MCP](../Sources/VaporSkeletonKit/VaporSkeletonKit.docc/Articles/ServidorMCP.md).

---

# 5. Arquitectura de pruebas

Se requieren tres niveles principales — para qué sirve cada uno y qué aporta este kit en
cada nivel está en
[Testing y E2E](../Sources/VaporSkeletonKit/VaporSkeletonKit.docc/Articles/TestingYE2E.md);
aquí solo el propósito de cada nivel como regla:

* **Unitarios** — lógica de negocio pura, mapeo modelo → DTO, validación,
  transformaciones deterministas. Sin HTTP, sin base de datos real. No deberían intentar
  reproducir infraestructura que pertenece a integración/E2E.
* **Integración** — comportamiento real de PostgreSQL, consultas Fluent, migraciones,
  persistencia, integración de la aplicación. PostgreSQL real, migraciones reales,
  aplicación completa montada.
* **E2E** — comportamiento observable por un consumidor externo: recorrido HTTP/MCP
  completo, límite real de autenticación, persistencia real, serialización, contratos de
  negocio críticos. Servidor real, transporte HTTP/MCP real, imagen Docker de
  producción, base de datos aislada, seed determinista.

---

# 6. Especificaciones de endpoints y MCP

Cada endpoint de API o herramienta MCP importante debería disponer de su propia
especificación.

Estructura recomendada:

```
docs/contracts/
    owners/
        GET-owners.md
        POST-owners.md
    accounts/
        ...
    mcp/
        list-owners.md
```

Especificación de endpoint REST:

1. Endpoint (método, path, `operationId`, body, parámetros)
2. Autenticación
3. Contrato de entrada
4. Contrato de salida
5. Comportamiento
6. Escenarios de error
7. Consumidores relacionados
8. Plan de pruebas (con una suite mínima de contrato, §8.1, separada del resto)
9. Escenarios de regresión de referencia
10. Comportamiento deliberadamente no probado

Especificación de herramienta MCP:

1. Definición
2. Autenticación
3. Contrato de entrada
4. Contrato de salida
5. Comportamiento
6. Escenarios de error
7. Plan de pruebas
8. Escenarios de regresión de referencia
9. Comportamiento deliberadamente no probado

El plan de pruebas es prescriptivo. Un escenario no se considera cubierto a menos que
exista un test explícito para él.

---

# 7. Estructura del plan de pruebas

Cada contrato debe distinguir Unitario / Integración / E2E. Ejemplo:

| Escenario | Unit. | Int. | E2E |
|---|:-:|:-:|:-:|
| Colección vacía | ✓ | ✓ | ✓ |
| Elemento único | ✓ | ✓ | ✓ |
| Múltiples elementos | ✓ | ✓ | ✓ |
| Campo opcional | ✓ | ✓ | ✓ |
| Fallo de base de datos | | ✓ | ✓ |
| Fallo de autenticación | | | ✓ |
| Autenticación correcta | | | ✓ |
| Contrato/esquema | | | ✓ |

No se deben crear tests simplemente para aumentar los porcentajes de cobertura. Los
tests deben proteger comportamiento observable o invariantes importantes.

---

# 3. Estrategia de seed E2E

El seed forma parte de la infraestructura de pruebas. Debe ser determinista,
documentado, mínimo, representativo y reproducible.

Debe preferirse un seed basado en la API cuando la propia API sea capaz de crear el
estado requerido (`POST /owners` → aplicación real → PostgreSQL) en lugar de INSERTs SQL
directos. El seed directo en base de datos es aceptable cuando el estado no pueda
crearse razonablemente mediante la API pública.

## 8.1 Identificadores deterministas

Cuando sea práctico, los registros creados por el seed deberían utilizar identificadores
deterministas o claves de búsqueda deterministas. Esto facilita la depuración de los
tests y evita depender del orden de creación.

## 8.2 Idempotencia

Preferentemente, un seed debería poder ejecutarse más de una vez de forma segura.
Posibles estrategias: crear-o-encontrar, claves externas deterministas, limpieza
controlada. La estrategia exacta dependerá del proyecto.

---

# 9. Estrategia de Neon

## 9.1 Rama base

Debe mantenerse una rama de base de datos estable (p. ej. `e2e-base`) que represente la
línea base del esquema para E2E: las migraciones actuales, ningún estado mutable
específico de tests, un esquema conocido y validado.

## 9.2 Ramas por ejecución

Cada ejecución E2E crea su propia rama desechable a partir de la base
(`e2e-base` → `e2e-run-001`, `e2e-run-002`, ...).

## 9.3 Ciclo de vida

Crear rama → obtener `DATABASE_URL` → ejecutar migraciones → iniciar aplicación → seed →
ejecutar E2E → recopilar diagnósticos → eliminar rama. La limpieza debe ejecutarse
incluso después de un fallo de los tests.

La mecánica concreta de este ciclo de vida se realiza mediante pruebas E2E locales con utilidades integradas en TestSupport.

## 9.4 Consideraciones del plan gratuito

La arquitectura debe respetar los límites del plan de Neon seleccionado. Si el proyecto
utiliza un plan gratuito, debe evitarse acumular ramas abandonadas — las pruebas locales
debe disponer de una limpieza fiable. Si las ejecuciones E2E concurrentes superan los
recursos disponibles de Neon, debe limitarse la concurrencia en lugar de compartir
silenciosamente el estado.

## 9.5 Fallos forzados en E2E

El escenario "fallo de base de datos" del plan de pruebas (§7) exige observar un error
real contra el artefacto de producción — pero el contenedor E2E principal lo comparten
el resto de escenarios del mismo run; no puede romperse su conexión sin invalidarlos a
todos.

Preferido: una segunda instancia efímera del mismo artefacto (misma imagen, ningún
cambio de código), configurada desde el arranque con una conexión a base de datos
deliberadamente inalcanzable, y sin ejecutar migraciones. Solo los escenarios que
necesitan observar ese fallo apuntan a esta segunda instancia; el resto sigue contra la
principal.

Debe evitarse cualquier vía de test (endpoint o variable de entorno que desactive la
conexión bajo demanda) dentro del código de producción para provocar el fallo — la
orquestación debe ser externa al artefacto, igual que exige §14-17 para cualquier otro
mecanismo de prueba.

---

# 10. Docker y Render

El Dockerfile debe representar la aplicación de producción: Dockerfile → build → E2E →
Render, sin una implementación E2E separada salvo razón justificada.

La aplicación debe recibir la configuración mediante variables de entorno (`DATABASE_URL`,
`WORKOS_ISSUER`, `WORKOS_RESOURCE_INDICATORS`, configuración MCP, `PORT`, ...). Nunca se
deben incluir secretos en el repositorio.

El `Dockerfile` es responsabilidad de cada proyecto consumidor — este kit no lo genera,
se debe usar en el entorno de validación local antes de desplegar.

---

# 11. Migraciones de base de datos

Las migraciones forman parte del contrato de despliegue. E2E debe validar que una base
de datos limpia puede llevarse al esquema esperado partiendo exclusivamente de las
migraciones: rama Neon limpia → migraciones → inicio de la aplicación → seed → tests.

No se debe depender de que el esquema de la base de datos local de un desarrollador sea
correcto.

---

# 12. Pruebas Locales y TestSupport

El pipeline de CI remoto desaparece a favor de validaciones y pruebas de integración y E2E en local.
Se utiliza el paquete de `TestSupport` para realizar inyecciones de errores ("programar" el servidor para fallar) de modo que se puedan verificar comportamientos complejos en local sin necesidad de pipelines remotos.

---

# 13. Despliegue en Render

Render debe ejecutar el mismo artefacto de aplicación que ha sido validado por CI: merge
→ build → tests → despliegue en Render → smoke test → éxito.

Si el despliegue falla o falla el smoke test, el proceso de despliegue debe proporcionar
un procedimiento definido de rollback o recuperación. La configuración exacta de Render
es específica de cada proyecto; la mecánica del smoke test post-despliegue se ejecuta vía scripts locales.

---

# 14. Estrategia «Free First»

La arquitectura base debe asumir: Neon Free, Render Free cuando resulte
adecuado, configuración de WorkOS apropiada para desarrollo/pruebas, y ausencia de
mecanismos de protección que requieran funcionalidades de pago.

Las funcionalidades de pago pueden documentarse como mejoras opcionales. La arquitectura
no debe depender de una funcionalidad cuya disponibilidad varíe según el plan del proveedor del repo.
En particular, **Workflow Execution Protections** debe considerarse opcional y no debe
constituir una dependencia de la arquitectura base.

---

# 15. Límites de seguridad

Los secretos deben mantenerse fuera del control de versiones. Entre los secretos
habituales se incluyen: credenciales de la API de Neon, credenciales de Render,
credenciales de WorkOS, claves de firma, configuración de autenticación MCP.

Nunca se deben exponer innecesariamente secretos de producción a código ejecutado desde
pull requests. Los pull requests procedentes de forks requieren especial consideración,
ya que los secretos pueden estar intencionadamente no disponibles para workflows que
ejecutan código no confiable.

La infraestructura local debe priorizar credenciales de corta duración o con permisos
limitados siempre que la plataforma lo permita.

---

# 16. Observabilidad y diagnósticos

Un fallo E2E debe poder diagnosticarse. El entorno local debería conservar, cuando resulte práctico:
salida de los tests, logs de la aplicación, logs de migraciones, salida del seed,
diagnósticos de peticiones/respuestas HTTP, logs de los contenedores, información de la
rama de Neon.

Cuando una base de datos desechable vaya a eliminarse, los diagnósticos útiles deben
recopilarse antes de realizar la limpieza.

---

# 17. Qué NO debe estandarizarse deliberadamente

No todos los detalles de implementación pertenecen a la arquitectura genérica. Deben
mantenerse específicos de cada proyecto: modelos de dominio, nombres de endpoints,
esquema exacto de la base de datos, registros exactos del seed, nombres de los servicios
de Render, IDs de proyectos de Neon, identificadores de tenant/configuración de WorkOS,
reglas de
autorización específicas del negocio.

El estándar genérico debe definir el patrón, no los datos del proyecto.

---

# 18. Estructura de repositorio recomendada

Una posible estructura base:

```
Sources/
  App/
    APIHandlers/
    Models/
    Services/
    MCP/
Tests/
  AppIntegrationTests/
  AppUnitTests/
  E2ESupport/
  E2ESeed/
  E2ETests/
docs/
  contracts/
    ...

Package.swift
```

La autenticación (`Security/` en un proyecto que la implementara localmente) hoy no vive
en el repositorio del proyecto en absoluto — es responsabilidad de `WorkOSBearerAuth`.
La estructura exacta puede adaptarse a un proyecto existente.

---

# 19. Checklist de adopción para nuevos proyectos

**Aplicación:** Vapor configurado · Fluent configurado · PostgreSQL configurado ·
migraciones establecidas · OpenAPI establecido · autenticación WorkOS establecida ·
servidor MCP establecido cuando sea necesario · revisado el uso compartido de lógica de
negocio REST/MCP.

**Testing:** tests unitarios · tests de integración · tests E2E · target de soporte E2E
· seed determinista · especificaciones de endpoints/herramientas · escenarios de
regresión de referencia.

**Infraestructura:** proyecto Neon · rama base E2E · ciclo de vida de ramas efímeras ·
servicio Render · pruebas locales · limpieza en caso de
fallo.

---

# 20. Cuestiones de diseño abiertas para este estándar

Este documento sigue siendo, en parte, un borrador. Estado de cada cuestión original:

1. Límites exactos de concurrencia y ciclo de vida de ramas en Neon Free. **Abierto** —
   se deben evitar ejecuciones superpuestas de tests locales para evitar errores de red y memoria, ya que no hay una cifra documentada de cuántas ramas efímeras concurrentes soporta el
   plan gratuito antes de degradar.

2. Estrategia automatizada para tokens de prueba de WorkOS. **Resuelto** — ver §4.2,
   "Dos lecciones ya resueltas por `WorkOSBearerAuth`" (Authorization Server falsa con
   clave de prueba fija, en vez de un token real de larga duración).

3. Estrategia de transporte y autenticación para E2E de MCP. **Resuelto** —
   `VaporSkeletonKitMCPE2ESupport` aporta un `E2EMCPClient` sobre `HTTPClientTransport`
   con el mismo patrón de `authToken` que el cliente REST; ver
   [Testing y E2E](../Sources/VaporSkeletonKit/VaporSkeletonKit.docc/Articles/TestingYE2E.md).

4. Si REST y MCP deben compartir siempre servicios de aplicación o únicamente cuando su
   semántica sea idéntica. **Abierto** — sigue siendo una decisión de diseño por
   proyecto, no una regla con respuesta única.

5. Plantillas estándar para los archivos de especificación de endpoints/herramientas.
    **Resuelto** — ver §6, estructura de `ENDPOINT-TEMPLATE.md`/`MCP-TOOL-TEMPLATE.md`.

Los puntos aún abiertos (1, 4) deberían resolverse antes de considerar el
documento un estándar organizativo definitivo.

---

# 21. Principio rector

La arquitectura general debe hacer que el camino seguro sea también el camino fácil:

```
El agente escribe código de aplicación → tests deterministas → base de datos real
y efímera → binario del servidor → validación local → despliegue → smoke test
```
