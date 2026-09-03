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
            let response = try await client.get("auth-echo", as: AuthEcho.self, authorization: .none)
            #expect(response.authorization == nil)
        }

        #expect(await recorder.called == false)
    }

    @Test("Attaches the token produced by authToken when authorization is .default")
    func authenticatedRequest() async throws {
        try await withRunningServer(port: 18092, mount: mountAuthEchoRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL, authToken: { "abc123" })
            let response = try await client.get("auth-echo", as: AuthEcho.self)
            #expect(response.authorization == "Bearer abc123")
        }
    }

    @Test(".bearer overrides authToken with an explicit token, without calling it")
    func explicitBearerToken() async throws {
        actor Recorder {
            private(set) var called = false
            func markCalled() { called = true }
        }
        let recorder = Recorder()

        try await withRunningServer(port: 18098, mount: mountAuthEchoRoute) { baseURL in
            let client = E2EHTTPClient(
                baseURL: baseURL,
                authToken: {
                    await recorder.markCalled()
                    return "unused-token"
                }
            )
            let response = try await client.get(
                "auth-echo", as: AuthEcho.self, authorization: .bearer("explicit-token")
            )
            #expect(response.authorization == "Bearer explicit-token")
        }

        #expect(await recorder.called == false)
    }

    @Test("post(json:as:) round-trips a JSON body")
    func postRoundTrip() async throws {
        try await withRunningServer(port: 18093, mount: mountEchoBodyRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.post("echo-body", json: Message(text: "hi"), as: Message.self)
            #expect(response == Message(text: "hi"))
        }
    }

    @Test("put(encoding:) sends a PUT with a JSON body")
    func putRoundTrip() async throws {
        try await withRunningServer(port: 18100, mount: mountEchoMethodAndBodyRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.put("echo-method-body", encoding: Message(text: "updated"))
            #expect(response.status == 200)
            let echoed = try JSONDecoder().decode(MethodAndBody.self, from: response.body)
            #expect(echoed.method == "PUT")
            #expect(echoed.body == "{\"text\":\"updated\"}")
        }
    }

    @Test("Response exposes lower-cased response headers")
    func responseHeaders() async throws {
        try await withRunningServer(port: 18097, mount: mountCustomHeaderRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.get("custom-header")
            #expect(response.headers["x-custom"] == "value")
        }
    }

    @Test("send(contentType:) overrides the default application/json Content-Type")
    func customContentType() async throws {
        try await withRunningServer(port: 18099, mount: mountEchoContentTypeRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.send(
                "POST", "echo-content-type", body: Data("plain text".utf8), contentType: "text/plain"
            )
            #expect(String(decoding: response.body, as: UTF8.self) == "text/plain")
        }
    }

    @Test("Throws unexpectedStatus for a non-200 response")
    func nonSuccessStatus() async throws {
        try await withRunningServer(port: 18094, mount: mountFailingRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            await #expect(throws: E2EHTTPError.self) {
                _ = try await client.get("boom", as: Message.self, authorization: .none)
            }
        }
    }
}

private struct MethodAndBody: Content {
    let method: String
    let body: String
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

private func mountEchoMethodAndBodyRoute(_ app: Application) throws {
    app.on(.PUT, "echo-method-body", body: .collect) { req -> MethodAndBody in
        MethodAndBody(method: req.method.rawValue, body: req.body.string ?? "")
    }
}

private func mountCustomHeaderRoute(_ app: Application) throws {
    app.get("custom-header") { _ -> Response in
        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: "X-Custom", value: "value")
        return response
    }
}

private func mountEchoContentTypeRoute(_ app: Application) throws {
    app.on(.POST, "echo-content-type", body: .collect) { req -> String in
        req.headers.first(name: .contentType) ?? "none"
    }
}
