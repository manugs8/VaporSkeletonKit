import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit
import Foundation // for setenv

/// Tests para `TestFaultInjectionMiddleware` (Ver ADR 0011).
@Suite(.serialized)
struct TestFaultInjectionTests {
    @Test("POST /_test/fault returns 404 when TEST_FAULT_INJECTION_ENABLED is not set")
    func routeNotMountedWhenFlagDisabled() async throws {
        // Forzamos "false" para no depender del estado dejado por otros tests.
        setenv("TEST_FAULT_INJECTION_ENABLED", "false", 1)
        
        let app = try await Application.make(.testing)
        do {
            registerTestFaultInjection(app)
            
            try await app.testing().test(.POST, "_test/fault") { res async in
                #expect(res.status == .notFound)
            }
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("An armed fault forces the next matching request's status, then reverts")
    func armedFaultFiresOnceThenReverts() async throws {
        setenv("TEST_FAULT_INJECTION_ENABLED", "true", 1)
        
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
        setenv("TEST_FAULT_INJECTION_ENABLED", "true", 1)
        
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
}
