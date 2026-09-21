import Foundation
import Testing
import Vapor
import VaporSkeletonKit
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

        try await withRunningServer(mount: mountAuthEchoRoute) { baseURL in
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
        try await withRunningServer(mount: mountAuthEchoRoute) { baseURL in
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

        try await withRunningServer(mount: mountAuthEchoRoute) { baseURL in
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
        try await withRunningServer(mount: mountEchoBodyRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.post("echo-body", json: Message(text: "hi"), as: Message.self)
            #expect(response == Message(text: "hi"))
        }
    }

    @Test("put(encoding:) sends a PUT with a JSON body")
    func putRoundTrip() async throws {
        try await withRunningServer(mount: mountEchoMethodAndBodyRoute) { baseURL in
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
        try await withRunningServer(mount: mountCustomHeaderRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.get("custom-header")
            #expect(response.headers["x-custom"] == "value")
        }
    }

    @Test("Doesn't crash when two response headers differ only by case")
    func duplicateCaseInsensitiveHeadersDoNotCrash() async throws {
        try await withRunningServer(mount: mountDuplicateCaseHeaderRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.get("duplicate-header")
            // No crashea; qué valor concreto "gana" entre dos cabeceras que solo
            // difieren en mayúsculas/minúsculas no es lo que se está probando aquí.
            #expect(response.headers["x-dup"] != nil)
        }
    }

    @Test("send(contentType:) overrides the default application/json Content-Type")
    func customContentType() async throws {
        try await withRunningServer(mount: mountEchoContentTypeRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.send(
                "POST", "echo-content-type", body: Data("plain text".utf8), contentType: "text/plain"
            )
            #expect(String(decoding: response.body, as: UTF8.self) == "text/plain")
        }
    }

    @Test("Throws unexpectedStatus for a non-200 response")
    func nonSuccessStatus() async throws {
        try await withRunningServer(mount: mountFailingRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            await #expect(throws: E2EHTTPError.self) {
                _ = try await client.get("boom", as: Message.self, authorization: .none)
            }
        }
    }

    @Test("post(json:as:) decodes a 201 Created response, not just 200")
    func postAsAccepts201() async throws {
        try await withRunningServer(mount: mountCreatedRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let created = try await client.post("items", json: Message(text: "hi"), as: Message.self)
            #expect(created == Message(text: "hi"))
        }
    }

    @Test("get(as:) decodes any 2xx response, not just 200")
    func getAsAccepts2xx() async throws {
        try await withRunningServer(mount: mountPartialContentRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let decoded = try await client.get("partial", as: Message.self)
            #expect(decoded == Message(text: "partial"))
        }
    }

    @Test("get(query:) attaches query items as a real query string, not mangled into the path")
    func queryStringIsAttachedCorrectly() async throws {
        try await withRunningServer(mount: mountEchoQueryRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.get(
                "echo-query", query: [URLQueryItem(name: "filter", value: "x"), URLQueryItem(name: "page", value: "2")]
            )
            #expect(String(decoding: response.body, as: UTF8.self) == "filter=x&page=2")
        }
    }

    /// `URLComponents.queryItems` deja `+` sin escapar, y el servidor lo decodifica como
    /// un espacio — p. ej. el offset de una fecha ISO-8601 (`+02:00`) usada como filtro.
    @Test("get(query:) preserves a literal + in a query value instead of turning it into a space")
    func queryStringPreservesPlusSign() async throws {
        try await withRunningServer(mount: mountEchoQueryRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let decoded = try await client.get(
                "echo-query-value",
                query: [URLQueryItem(name: "from", value: "2026-09-21T10:00:00+02:00")],
                as: Message.self
            )
            #expect(decoded == Message(text: "2026-09-21T10:00:00+02:00"))
        }
    }

    @Test("get(query:as:) round-trips query items through the decoding overload too")
    func queryStringWithDecoding() async throws {
        try await withRunningServer(mount: mountEchoQueryRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let response = try await client.get(
                "echo-query-json", query: [URLQueryItem(name: "q", value: "widgets")], as: Message.self
            )
            #expect(response == Message(text: "q=widgets"))
        }
    }

    /// Extremo a extremo, contra un servidor real con el modo E2E activado — no un
    /// stub del middleware. Prueba el contrato completo cliente↔servidor:
    /// `armFault` (que hace `POST /_test/fault`), la ruta real viéndose interceptada
    /// una única vez, y volviendo a responder con normalidad después.
    @Test("armFault: a request to the armed route receives the configured status, once")
    func armFaultEndToEnd() async throws {
        try await withRunningServer(mount: mountArmableFlakyRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            try await client.armFault(method: "GET", path: "/flaky", status: 503)

            let faulted = try await client.get("flaky", authorization: .none)
            #expect(faulted.status == 503)

            let afterward = try await client.get("flaky", authorization: .none)
            #expect(afterward.status == 200)
        }
    }

    /// Cubre la mejora propuesta en `TODO.md` §1: un test puede armar un fallo que imite
    /// el contrato de error real de su propia app (p. ej. un `AbortError` de Vapor) en vez
    /// de quedarse con la `FaultBody` fija de `TestFaultInjectionMiddleware`.
    @Test("armFault(body:headers:): the faulted response echoes back the custom body and headers")
    func armFaultWithCustomBodyEndToEnd() async throws {
        try await withRunningServer(mount: mountArmableFlakyRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            let customBody = Data(#"{"error":true,"reason":"Database connection lost"}"#.utf8)
            try await client.armFault(
                method: "GET", path: "/flaky", status: 500,
                body: customBody, headers: ["X-Fault-Reason": "db-down"]
            )

            let faulted = try await client.get("flaky", authorization: .none)
            #expect(faulted.status == 500)
            #expect(faulted.body == customBody)
            #expect(faulted.headers["content-type"] == "application/json")
            #expect(faulted.headers["x-fault-reason"] == "db-down")

            // Consumido: la siguiente petición vuelve al handler real.
            let afterward = try await client.get("flaky", authorization: .none)
            #expect(afterward.status == 200)
        }
    }

    @Test("armFault(encoding:): encodes an Encodable body to JSON automatically")
    func armFaultWithEncodableBodyEndToEnd() async throws {
        try await withRunningServer(mount: mountArmableFlakyRoute) { baseURL in
            let client = E2EHTTPClient(baseURL: baseURL)
            try await client.armFault(
                method: "GET", path: "/flaky", status: 422, encoding: Message(text: "validation failed")
            )

            let faulted = try await client.get("flaky", authorization: .none)
            #expect(faulted.status == 422)
            let decoded = try JSONDecoder.e2e.decode(Message.self, from: faulted.body)
            #expect(decoded == Message(text: "validation failed"))
        }
    }

    /// `session.data(for:)` no siempre devuelve un `HTTPURLResponse` — un `file://`
    /// nunca lo es. `send(...)` debe reportarlo como ``E2EHTTPError/unexpectedStatus``
    /// con status `-1` en vez de forzar el cast y crashear.
    @Test("Throws unexpectedStatus(-1, ...) when the response isn't an HTTPURLResponse")
    func nonHTTPResponseYieldsStatusMinusOne() async throws {
        let directory = FileManager.default.temporaryDirectory
        let fileName = "e2ehttpclient-non-http-\(UUID().uuidString).txt"
        try Data("not a real HTTP server".utf8).write(to: directory.appendingPathComponent(fileName))
        defer { try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName)) }

        let client = E2EHTTPClient(baseURL: directory)
        do {
            _ = try await client.get(fileName, authorization: .none)
            Issue.record("Expected E2EHTTPError.unexpectedStatus")
        } catch let E2EHTTPError.unexpectedStatus(status, _) {
            #expect(status == -1)
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

private func mountDuplicateCaseHeaderRoute(_ app: Application) throws {
    app.get("duplicate-header") { _ -> Response in
        let response = Response(status: .ok)
        // Dos cabeceras que solo difieren en mayúsculas/minúsculas — HTTP las trata
        // como el mismo nombre, pero llegan como entradas separadas a
        // HTTPURLResponse.allHeaderFields en el cliente.
        response.headers.add(name: "X-Dup", value: "first")
        response.headers.add(name: "x-dup", value: "second")
        return response
    }
}

private func mountEchoContentTypeRoute(_ app: Application) throws {
    app.on(.POST, "echo-content-type", body: .collect) { req -> String in
        req.headers.first(name: .contentType) ?? "none"
    }
}

private func mountCreatedRoute(_ app: Application) throws {
    app.on(.POST, "items", body: .collect) { req -> Response in
        let message = try req.content.decode(Message.self)
        let response = Response(status: .created)
        try response.content.encode(message)
        return response
    }
}

private func mountPartialContentRoute(_ app: Application) throws {
    app.get("partial") { _ -> Response in
        let response = Response(status: .partialContent)
        try response.content.encode(Message(text: "partial"))
        return response
    }
}

private func mountEchoQueryRoute(_ app: Application) throws {
    app.get("echo-query") { req -> String in
        req.url.query ?? ""
    }
    app.get("echo-query-json") { req -> Message in
        Message(text: req.url.query ?? "")
    }
    // Decodifica el valor como lo haría un handler real (req.query), no la query cruda.
    app.get("echo-query-value") { req -> Message in
        Message(text: try req.query.get(String.self, at: "from"))
    }
}

private func mountArmableFlakyRoute(_ app: Application) throws {
    try registerE2EMode(app, scenarioFactory: UnusedScenarioFactory())
    app.get("flaky") { _ in Response(status: .ok) }
}

private struct UnusedScenarioFactory: E2EScenarioFactory {
    func make(scenario: String) throws -> any E2EScenario {
        fatalError("armFaultEndToEnd doesn't exercise /e2e/prepare")
    }
}
