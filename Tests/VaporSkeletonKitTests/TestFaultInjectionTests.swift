import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit

/// Tests para `TestFaultInjectionMiddleware`.
@Suite(.serialized)
struct TestFaultInjectionTests {
    @Test("An armed fault forces the next matching request's status, then reverts")
    func armedFaultFiresOnceThenReverts() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)
            
            app.get("owners") { _ in
                return Response(status: .ok)
            }
            
            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(method: "GET", path: "/owners", status: 500, delayMilliseconds: nil)
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .internalServerError)
            })

            // El fallo armado se consume al primer uso. Luego ejecuta el handler real.
            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("DELETE /_test/fault clears an armed fault without consuming it via a real request")
    func deleteClearsArmedFault() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)
            
            app.get("owners") { _ in
                return Response(status: .ok)
            }
            
            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(method: "GET", path: "/owners", status: 500, delayMilliseconds: nil)
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(.DELETE, "_test/fault", afterResponse: { res async in
                #expect(res.status == .ok)
            })

            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Rejects a status outside 100...599 with 400, without arming anything")
    func rejectsOutOfRangeStatus() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }

            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(method: "GET", path: "/owners", status: 99999, delayMilliseconds: nil)
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )

            // Nada quedó armado — la petición real sigue respondiendo con normalidad.
            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// El middleware vive en `.beginning`, por fuera de `ErrorMiddleware` — un error de
    /// decodificación que se escapara no llegaría a ser una respuesta HTTP (sobre un
    /// servidor real, Vapor cerraría la conexión sin responder).
    @Test("Rejects a malformed body with 400 instead of letting the decoding error escape")
    func rejectsMalformedBody() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: #"{"method":"GET","path":"/owners"}"#)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Rejects a delayMilliseconds above the cap with 400, without arming anything")
    func rejectsExcessiveDelay() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }

            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(
                            method: "GET", path: "/owners", status: 500,
                            delayMilliseconds: TestFaultInjectionMiddleware.maxDelayMilliseconds + 1
                        )
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )

            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("An armed delayMilliseconds actually delays the faulted response")
    func delaysBeforeRespondingWithTheFault() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }

            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(
                            method: "GET", path: "/owners", status: 500, delayMilliseconds: 200
                        )
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            let start = ContinuousClock.now
            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .internalServerError)
            })
            let elapsed = ContinuousClock.now - start

            #expect(elapsed >= .milliseconds(200))
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// El fallo se arma por la clave exacta `"MÉTODO ruta"` (``FaultInjectionStore``) —
    /// una petición que no coincida en método o en ruta debe atravesar el middleware sin
    /// efecto alguno, y el fallo debe seguir armado para cuando sí llegue la petición
    /// correcta.
    @Test("Requests that don't match the armed method or path pass through untouched")
    func passesThroughRequestsThatDontMatch() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }
            app.post("owners") { _ in Response(status: .ok) }
            app.get("pets") { _ in Response(status: .ok) }

            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(method: "GET", path: "/owners", status: 500, delayMilliseconds: nil)
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            // Mismo path, método distinto.
            try await app.testing().test(.POST, "owners", afterResponse: { res async in
                #expect(res.status == .ok)
            })
            // Mismo método, path distinto.
            try await app.testing().test(.GET, "pets", afterResponse: { res async in
                #expect(res.status == .ok)
            })

            // El fallo armado sigue intacto — ninguna de las peticiones anteriores lo consumió.
            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .internalServerError)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Cubre la mejora propuesta en `TODO.md` §1: un consumidor puede armar un fallo que
    /// devuelva su propio contrato de error (p. ej. el de un `AbortError` de Vapor) en vez
    /// de quedarse con la `FaultBody` fija.
    @Test("An armed fault with a custom body echoes it back verbatim, with an application/json Content-Type")
    func armedFaultWithCustomBodyEchoesItBack() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }

            let customBody = #"{"error":true,"reason":"Database connection lost"}"#
            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(
                            method: "GET", path: "/owners", status: 500, delayMilliseconds: nil,
                            body: customBody
                        )
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .internalServerError)
                #expect(res.headers.contentType?.description == "application/json")
                #expect(res.body.string == customBody)
            })

            // Consumido: la siguiente petición vuelve al handler real, no a FaultBody ni al body custom.
            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("An armed fault's custom headers are added to the faulted response")
    func armedFaultWithCustomHeaders() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }

            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(
                            method: "GET", path: "/owners", status: 503, delayMilliseconds: nil,
                            body: #"{"error":"unavailable"}"#,
                            headers: ["Retry-After": "5", "X-Fault-Reason": "maintenance"]
                        )
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .serviceUnavailable)
                #expect(res.headers.first(name: "Retry-After") == "5")
                #expect(res.headers.first(name: "X-Fault-Reason") == "maintenance")
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// `headers` puede incluir `Content-Type` explícitamente para sobreescribir el
    /// `application/json` por defecto — p. ej. un consumidor cuyo `ErrorMiddleware`
    /// respondiera texto plano en vez de JSON.
    @Test("A custom header can override the default Content-Type for the faulted response")
    func customHeaderOverridesDefaultContentType() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }

            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(
                            method: "GET", path: "/owners", status: 500, delayMilliseconds: nil,
                            body: "internal error", headers: ["Content-Type": "text/plain; charset=utf-8"]
                        )
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .internalServerError)
                #expect(res.headers.contentType?.description == "text/plain; charset=utf-8")
                #expect(res.body.string == "internal error")
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Rejects a body larger than the cap with 400, without arming anything")
    func rejectsExcessiveBody() async throws {
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)

            app.get("owners") { _ in Response(status: .ok) }

            let oversizedBody = String(repeating: "x", count: TestFaultInjectionMiddleware.maxBodyBytes + 1)
            try await app.testing().test(
                .POST, "_test/fault",
                beforeRequest: { req in
                    try req.content.encode(
                        TestFaultInjectionMiddleware.ArmRequest(
                            method: "GET", path: "/owners", status: 500, delayMilliseconds: nil,
                            body: oversizedBody
                        )
                    )
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )

            // Nada quedó armado — la petición real sigue respondiendo con normalidad.
            try await app.testing().test(.GET, "owners", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
