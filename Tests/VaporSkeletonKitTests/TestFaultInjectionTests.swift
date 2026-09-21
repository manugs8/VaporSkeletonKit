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
}
