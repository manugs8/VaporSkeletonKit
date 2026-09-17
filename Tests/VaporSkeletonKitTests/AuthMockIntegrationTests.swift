import Testing
import Vapor
import VaporTesting
@testable import VaporSkeletonKit
import AuthMockServer

@Suite("AuthMock Integration Tests")
struct AuthMockIntegrationTests {
    @Test("El mock arranca en memoria y responde al HTTP Testing framework")
    func testAuthMockServerStartsInProcess() async throws {
        let authMockApp = try await Application.make(.testing)
        
        let config = Config(environment: ["AUTHMOCK_PORT": "0", "AUTHMOCK_STATUS": "401"])
        let statusOverride = StatusOverrideBox()
        let claimsOverride = ClaimsOverrideBox()
        
        try routes(
            authMockApp,
            config: config,
            statusOverride: statusOverride,
            claimsOverride: claimsOverride
        )
        
        
        try await authMockApp.testing().test(.POST, "token", afterResponse: { res async throws in
            #expect(res.status == .unauthorized)
        })
        
        await statusOverride.arm(200)
        
        try await authMockApp.testing().test(.POST, "token", afterResponse: { res async throws in
            #expect(res.status == .ok)
        })

        try await authMockApp.asyncShutdown()
    }
}
