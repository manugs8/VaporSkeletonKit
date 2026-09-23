import Foundation
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitE2ESupport

@Suite("E2EScenarioLifecycle")
struct E2EScenarioLifecycleTests {
    @Test("Reads the raw scenario from its own environment variable and hands it to prepare")
    func passesRawScenarioToPrepare() async throws {
        try await withRunningServer(mount: mountPingRoute) { baseURL in
            let variable = uniqueEnvironmentVariable()
            try await withEnvironment(variable, "some-scenario") {
                let received = RecordedValue<String>()
                let lifecycle = E2EScenarioLifecycle(environmentVariable: variable, baseURL: baseURL) { raw, client in
                    await received.set(raw)
                    _ = try await client.get("ping")
                }

                try await lifecycle.wait()
                #expect(await received.get() == "some-scenario")
            }
        }
    }

    @Test("Throws a readable error, not a crash, when the environment variable is missing")
    func missingScenarioFailsCleanly() async throws {
        let variable = uniqueEnvironmentVariable()
        let lifecycle = E2EScenarioLifecycle(environmentVariable: variable) { _, _ in }

        await #expect {
            try await lifecycle.wait()
        } throws: { error in
            guard case E2EPersistentServerError.missingScenario(let reportedVariable) = error else { return false }
            return reportedVariable == variable
        }
    }

    @Test("Throws a readable error, not a crash, when the server is unreachable")
    func unreachableServerFailsCleanly() async throws {
        let variable = uniqueEnvironmentVariable()
        try await withEnvironment(variable, "some-scenario") {
            let unreachable = URL(string: "http://127.0.0.1:1")!
            let lifecycle = E2EScenarioLifecycle(environmentVariable: variable, baseURL: unreachable) { _, client in
                _ = try await client.get("ping")
            }

            await #expect {
                try await lifecycle.wait()
            } throws: { error in
                guard case E2EPersistentServerError.serverUnreachable(let baseURL, _) = error else { return false }
                return baseURL == unreachable
            }
        }
    }

    @Test("Prepares the scenario at most once, no matter how many callers wait() concurrently")
    func preparesOnlyOnce() async throws {
        try await withRunningServer(mount: mountPingRoute) { baseURL in
            let variable = uniqueEnvironmentVariable()
            try await withEnvironment(variable, "some-scenario") {
                let callCount = RecordedValue<Int>(initial: 0)
                let lifecycle = E2EScenarioLifecycle(environmentVariable: variable, baseURL: baseURL) { _, client in
                    await callCount.increment()
                    _ = try await client.get("ping")
                }

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0..<10 {
                        group.addTask { try await lifecycle.wait() }
                    }
                    try await group.waitForAll()
                }

                #expect(await callCount.get() == 1)
            }
        }
    }

    @Test("withPersistentServer waits for preparation and hands back a working client")
    func withPersistentServerEndToEnd() async throws {
        try await withRunningServer(mount: mountPingRoute) { baseURL in
            let variable = uniqueEnvironmentVariable()
            try await withEnvironment(variable, "some-scenario") {
                let lifecycle = E2EScenarioLifecycle(environmentVariable: variable, baseURL: baseURL) { _, _ in }

                try await withPersistentServer(lifecycle, baseURL: baseURL) { client in
                    let response = try await client.get("ping")
                    #expect(response.status == 200)
                }
            }
        }
    }
}

private func mountPingRoute(_ app: Application) throws {
    app.get("ping") { _ in "pong" }
}

/// Un nombre distinto por test evita que tests de este archivo (que corren en paralelo
/// por defecto) se pisen leyendo/escribiendo la misma variable de entorno real — más
/// simple que serializar el `@Suite` entero solo por esto.
private func uniqueEnvironmentVariable() -> String {
    "E2E_SCENARIO_LIFECYCLE_TEST_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
}

/// Igual que el `environment:` de `withTestApp` (`VaporSkeletonKitTesting`, no importable
/// desde este target de test): establece `value` vía `setenv`, y la restaura (o la
/// elimina, si no existía) al terminar — incluso si `body` lanza.
private func withEnvironment(_ key: String, _ value: String, _ body: () async throws -> Void) async throws {
    let original = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)
    defer {
        if let original {
            setenv(key, original, 1)
        } else {
            unsetenv(key)
        }
    }
    try await body()
}

private actor RecordedValue<Value> {
    private var value: Value?

    init(initial: Value? = nil) {
        self.value = initial
    }

    func set(_ newValue: Value) {
        value = newValue
    }

    func increment() where Value == Int {
        value = (value ?? 0) + 1
    }

    func get() -> Value {
        guard let value else {
            fatalError("RecordedValue read before any value was set")
        }
        return value
    }
}
