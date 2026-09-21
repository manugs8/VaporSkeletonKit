import Testing
import Vapor

@testable import VaporSkeletonKit

/// Ejercita el núcleo interno `runApp(_:configure:)` contra `Application.make(.testing)`
/// en lugar del entrypoint público `runApp(configure:)` — este último llama a
/// `LoggingSystem.bootstrap(from:)`, que solo puede ejecutarse una vez por proceso y
/// por tanto no es algo que una suite de tests pueda invocar repetidamente.
@Suite("Run App")
struct RunAppTests {
    @Test("Calls configure with the booted Application before serving")
    func callsConfigureBeforeServing() async throws {
        actor Recorder {
            private(set) var received = false
            func markReceived() { received = true }
        }
        let recorder = Recorder()
        struct StopEarly: Error {}

        let app = try await Application.make(.testing)
        await #expect(throws: StopEarly.self) {
            try await runApp(app) { app in
                await recorder.markReceived()
                _ = app.logger
                throw StopEarly()
            }
        }
        #expect(await recorder.received)
    }

    @Test("Propagates a configure error, shutting the Application down instead of serving")
    func propagatesConfigureErrors() async throws {
        struct BoomError: Error, Equatable {}

        let app = try await Application.make(.testing)
        await #expect(throws: BoomError.self) {
            try await runApp(app) { _ in throw BoomError() }
        }
    }

    @Test("Shuts the Application down if execute() throws too, not just if configure() does")
    func shutsDownWhenExecuteThrows() async throws {
        actor ShutdownFlag {
            private(set) var wasShutdown = false
            func markShutdown() { wasShutdown = true }
        }
        struct ShutdownRecorder: LifecycleHandler {
            let flag: ShutdownFlag
            func shutdownAsync(_ application: Application) async {
                await flag.markShutdown()
            }
        }

        // Ocupa un puerto primero, para que el intento de bind dentro de execute()
        // falle rápido y de forma determinista (dirección ya en uso), en vez de que
        // execute() sirva tráfico real indefinidamente.
        let blocker = try await Application.make(.testing)
        blocker.http.server.configuration.port = 0
        try await blocker.asyncBoot()
        try blocker.server.start()

        guard let port = blocker.http.server.shared.localAddress?.port else {
            await blocker.server.shutdown()
            try? await blocker.asyncShutdown()
            Issue.record("No se pudo determinar el puerto local del bloqueador")
            return
        }

        let app = try await Application.make(.testing)
        app.http.server.configuration.port = port
        let flag = ShutdownFlag()
        app.lifecycle.use(ShutdownRecorder(flag: flag))

        await #expect(throws: (any Error).self) {
            try await runApp(app) { _ in }
        }

        #expect(await flag.wasShutdown)

        await blocker.server.shutdown()
        try? await blocker.asyncShutdown()
    }
}
