import Fluent
import Foundation
import Testing
import Vapor
import VaporSkeletonKit
import VaporSkeletonKitTesting

// .serialized: varios tests mutan la misma variable de entorno global
// (VAPOR_SKELETON_KIT_TESTING_FLAG) para comprobar su restauración — en paralelo se
// pisarían entre sí.
@Suite("With Test App", .serialized)
struct WithTestAppTests {
    @Test("Configures, migrates, runs the test body, then reverts and shuts down")
    func happyPath() async throws {
        var sawApp = false

        try await withTestApp(configure: configureTestDatabase) { app in
            sawApp = true
            #expect(app.environment == .testing)
        }

        #expect(sawApp)
    }

    @Test("Sets the given environment variables before Application.make(.testing) runs")
    func setsEnvironment() async throws {
        unsetenv("VAPOR_SKELETON_KIT_TESTING_FLAG")

        try await withTestApp(
            environment: ["VAPOR_SKELETON_KIT_TESTING_FLAG": "true"],
            configure: configureTestDatabase
        ) { _ in
            #expect(ProcessInfo.processInfo.environment["VAPOR_SKELETON_KIT_TESTING_FLAG"] == "true")
        }
    }

    @Test("Propagates an error thrown by the test body, after still reverting/shutting down")
    func propagatesTestErrors() async throws {
        struct BoomError: Error {}

        await #expect(throws: BoomError.self) {
            try await withTestApp(configure: configureTestDatabase) { _ in
                throw BoomError()
            }
        }
    }

    /// Ver V11 en el informe de auditoría: `withTestApp` establecía variables de
    /// entorno vía `setenv` para la duración del test, pero nunca las revertía —
    /// contaminando el proceso (y, por tanto, los tests que se ejecutaran después en el
    /// mismo proceso) con el valor de test para siempre.
    @Test("Unsets a variable that had no previous value, once the body finishes")
    func restoresPreviouslyUnsetVariable() async throws {
        unsetenv("VAPOR_SKELETON_KIT_TESTING_FLAG")

        try await withTestApp(
            environment: ["VAPOR_SKELETON_KIT_TESTING_FLAG": "true"],
            configure: configureTestDatabase
        ) { _ in
            #expect(ProcessInfo.processInfo.environment["VAPOR_SKELETON_KIT_TESTING_FLAG"] == "true")
        }

        #expect(ProcessInfo.processInfo.environment["VAPOR_SKELETON_KIT_TESTING_FLAG"] == nil)
    }

    @Test("Restores a variable's previous value, once the body finishes")
    func restoresPreviousVariableValue() async throws {
        setenv("VAPOR_SKELETON_KIT_TESTING_FLAG", "original", 1)

        try await withTestApp(
            environment: ["VAPOR_SKELETON_KIT_TESTING_FLAG": "true"],
            configure: configureTestDatabase
        ) { _ in
            #expect(ProcessInfo.processInfo.environment["VAPOR_SKELETON_KIT_TESTING_FLAG"] == "true")
        }

        #expect(ProcessInfo.processInfo.environment["VAPOR_SKELETON_KIT_TESTING_FLAG"] == "original")
        unsetenv("VAPOR_SKELETON_KIT_TESTING_FLAG")
    }

    @Test("Restores the environment even when the test body throws")
    func restoresEnvironmentWhenBodyThrows() async throws {
        struct BoomError: Error {}
        unsetenv("VAPOR_SKELETON_KIT_TESTING_FLAG")

        await #expect(throws: BoomError.self) {
            try await withTestApp(
                environment: ["VAPOR_SKELETON_KIT_TESTING_FLAG": "true"],
                configure: configureTestDatabase
            ) { _ in
                throw BoomError()
            }
        }

        #expect(ProcessInfo.processInfo.environment["VAPOR_SKELETON_KIT_TESTING_FLAG"] == nil)
    }
}

private func configureTestDatabase(_ app: Application) throws {
    app.databases.use(
        try makePostgresConfiguration(from: PostgresEnvironmentConfig(
            databaseURL: Environment.get("DATABASE_URL"),
            host: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
            username: Environment.get("DATABASE_USERNAME") ?? "postgres",
            password: Environment.get("DATABASE_PASSWORD") ?? "postgres",
            database: Environment.get("DATABASE_NAME") ?? "postgres",
            tlsDisabled: Environment.get("DATABASE_TLS") != "require"
        )),
        as: .psql
    )
}
