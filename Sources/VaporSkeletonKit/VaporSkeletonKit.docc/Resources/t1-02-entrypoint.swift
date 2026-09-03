import Vapor
import VaporSkeletonKit

@main
enum Entrypoint {
    static func main() async throws {
        try await runApp(configure: configure)
    }
}
