import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit

/// Tests para `TestFaultInjectionMiddleware` (Ver ADR 0011).
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
}
