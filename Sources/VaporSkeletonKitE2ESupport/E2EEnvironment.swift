import Foundation

/// Where an E2E suite finds the server under test — real HTTP/MCP over the network via
/// ``E2EHTTPClient``/``E2EMCPClient``, never an in-process `Application`.
///
/// Reads `E2E_BASE_URL`, defaulting to `swift run`'s default local address so E2E tests
/// work against a manually started server. CI typically points this at a container
/// running the production Docker image instead.
public enum E2EEnvironment {
    public static var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["E2E_BASE_URL"] ?? "http://127.0.0.1:8080")!
    }
}
