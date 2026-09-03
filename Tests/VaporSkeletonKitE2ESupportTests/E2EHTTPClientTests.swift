import Testing
import Vapor
import VaporSkeletonKitE2ESupport

@Suite("E2E HTTP Client")
struct E2EHTTPClientTests {
    @Test("Sends no Authorization header when authenticated is false, and never calls authToken")
    func unauthenticatedRequest() async throws {
        actor Recorder {
            private(set) var called = false
            func markCalled() { called = true }
        }
        let recorder = Recorder()

        try await withRunningServer(port: 18091, mount: mountAuthEchoRoute) { baseURL in
            let client = E2EHTTPClient(
                baseURL: baseURL,
                authToken: {
                    await recorder.markCalled()
                    return "unused-token"
                }
            )
            let response = try await client.get("auth-echo", as: AuthEcho.self, authenticated: false)
            #expect(response.authorization == nil)
        }

        #expect(await recorder.called == false)
    }

    @Test("Attaches the token produced by authToken when authenticated")
    func authenticatedRequest() async throws {
        try await withRunningServer(port: 18092, mount: mountAuthEchoRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL, authToken: { "abc123" })
            let response = try await client.get("auth-echo", as: AuthEcho.self)
            #expect(response.authorization == "Bearer abc123")
        }
    }

    @Test("post(json:as:) round-trips a JSON body")
    func postRoundTrip() async throws {
        try await withRunningServer(port: 18093, mount: mountEchoBodyRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.post("echo-body", json: Message(text: "hi"), as: Message.self)
            #expect(response == Message(text: "hi"))
        }
    }

    @Test("Throws unexpectedStatus for a non-200 response")
    func nonSuccessStatus() async throws {
        try await withRunningServer(port: 18094, mount: mountFailingRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            await #expect(throws: E2EHTTPError.self) {
                _ = try await client.get("boom", as: Message.self, authenticated: false)
            }
        }
    }
}

private struct AuthEcho: Content {
    let authorization: String?
}

private struct Message: Content, Equatable {
    let text: String
}

private func mountAuthEchoRoute(_ app: Application) throws {
    app.get("auth-echo") { req -> AuthEcho in
        AuthEcho(authorization: req.headers.first(name: .authorization))
    }
}

private func mountEchoBodyRoute(_ app: Application) throws {
    app.post("echo-body") { req -> Message in
        try req.content.decode(Message.self)
    }
}

private func mountFailingRoute(_ app: Application) throws {
    app.get("boom") { _ -> Message in
        throw Abort(.internalServerError, reason: "boom")
    }
}
