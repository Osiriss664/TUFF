import Darwin
import Foundation
import Testing
@testable import TUFFEngine
@testable import TUFFServerCore

private actor AnsweringBackend: ServerInferenceBackend {
    func generate(
        _ request: ValidatedChatRequest,
        onEvent: @escaping @Sendable (ServerInferenceEvent) -> Void
    ) async throws -> ServerCompletion {
        onEvent(.content("ok"))
        return ServerCompletion(
            content: "ok", toolCalls: [], finishReason: "stop",
            usage: OpenAIUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2))
    }
}

/// Unload calls that got past the checks.
private final class UnloadCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// A web page can point its own domain at 127.0.0.1 (DNS rebinding), and the
/// browser then sends that domain as Host and Origin. Only this Mac's own
/// loopback names are served.
@Suite("Server host check", .serialized)
struct ServerHostCheckTests {
    private static let chatBody =
        #"{"model":"test-model","messages":[{"role":"user","content":"hi"}]}"#
    private static let token = String(repeating: "a", count: 64)

    /// A server with the control routes, staging under a root of its own.
    /// `unloads` counts unload calls that got past the checks.
    private static func makeServer(root: URL, unloads: UnloadCount) -> TUFFHTTPServer {
        let provider = FixedServerModelProvider(
            modelID: "test-model", backend: AnsweringBackend(), dialect: .gemma,
            visionCapability: "ready", queueLimit: 1)
        let control = ServerControl(
            token: token,
            status: {
                ServerControlStatus(
                    version: "test", mode: "test", residentModel: nil, transition: nil,
                    activeRequests: 0, queuedRequests: 0, idleUnloadInSeconds: nil,
                    defaultModel: "test-model", unloadDelaySeconds: 0)
            },
            unloadIfIdle: {
                unloads.add()
                return true
            })
        return TUFFHTTPServer(provider: provider, control: control, attachmentRoot: root)
    }

    private static func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("host-check-\(UUID().uuidString)", isDirectory: true)
    }

    private static func stagedFileCount(_ root: URL) -> Int {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var count = 0
        for case let url as URL in walker
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            count += 1
        }
        return count
    }

    /// One request as raw text, so Host and Origin are exactly what a test says.
    private static func request(method: String, path: String, headers: [String],
                                body: String = "", version: String = "HTTP/1.1",
                                connection: String = "close") -> String {
        var text = "\(method) \(path) \(version)\r\n"
        for line in headers { text += line + "\r\n" }
        if method == "POST" {
            text += "Content-Type: application/json\r\n"
                + "Content-Length: \(body.utf8.count)\r\n"
        }
        return text + "Connection: \(connection)\r\n\r\n" + body
    }

    /// Reads one small JSON response: the status line, headers and body.
    private static func readResponse(_ socket: Int32) throws -> String {
        try readUntil(socket: socket, timeoutMilliseconds: 4_000) {
            guard let split = $0.range(of: "\r\n\r\n") else { return false }
            return $0[split.upperBound...].hasSuffix("}")
        }
    }

    private static func send(port: Int, method: String, path: String,
                             headers: [String], version: String = "HTTP/1.1") throws -> String {
        let socket = try connectedSocket(port: port)
        defer { _ = Darwin.close(socket) }
        try writeAll(socket: socket, text: request(
            method: method, path: path, headers: headers,
            body: method == "POST" ? chatBody : "", version: version))
        return try readResponse(socket)
    }

    private static let routes = [
        ("POST", "/v1/chat/completions", [String]()),
        ("POST", "/v1/messages", []),
        ("POST", "/v1/responses", []),
        ("GET", "/v1/models", []),
        ("GET", "/health", []),
        ("GET", ServerControl.statusPath, []),
        ("POST", ServerControl.unloadPath, ["Authorization: Bearer \(token)"]),
    ]

    @Test func rebindingHostsAndForeignOriginsAreRefused() async throws {
        let root = Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let unloads = UnloadCount()
        let server = Self.makeServer(root: root, unloads: unloads)
        let channel = try await server.start(port: 0)
        let port = try #require(channel.localAddress?.port)
        let local = "Host: 127.0.0.1:\(port)"

        let refused: [[String]] = [
            ["Host: attacker.example:\(port)"],
            ["Host: attacker.example"],
            ["Host: 127.0.0.1.attacker.example:\(port)"],
            ["Host: localhost.attacker.example"],
            // Browsers resolve every *.localhost name to loopback themselves.
            ["Host: x.localhost:\(port)"],
            ["Host: 0.0.0.0:\(port)"],
            ["Host: 192.168.1.20:\(port)"],
            ["Host: "],
            ["Host: 127.0.0.1:abc"],
            [local, "Origin: http://attacker.example"],
            [local, "Origin: null"],
            [local, "Origin: http://localhost.attacker.example:3000"],
            [local, "Origin: http://localhost@attacker.example"],
            [local, "Origin: http://127.0.0.1:80@attacker.example"],
            [local, "Origin: http://localhost:3000", "Origin: http://attacker.example"],
        ]
        for headers in refused {
            for (method, path, extra) in Self.routes {
                let response = try Self.send(port: port, method: method, path: path,
                                             headers: headers + extra)
                #expect(response.hasPrefix("HTTP/1.1 403"), "\(headers) \(path)")
                // The Messages API error carries no code, only the message.
                #expect(response.contains(path == "/v1/messages"
                    ? "only answers requests addressed to" : "forbidden_host"),
                        "\(headers) \(path)")
                #expect(!response.contains("test-model"), "\(headers) \(path)")
            }
        }
        #expect(unloads.value == 0)
        try await server.shutdown()
    }

    /// Two Host lines must reach the handler and be refused there. If the
    /// HTTP parser ever rejects them first, this fails with a 400 and shows it.
    @Test func aSecondHostLineIsRefused() async throws {
        let root = Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Self.makeServer(root: root, unloads: UnloadCount())
        let channel = try await server.start(port: 0)
        let port = try #require(channel.localAddress?.port)

        for hosts in [["Host: 127.0.0.1:\(port)", "Host: attacker.example"],
                      ["Host: attacker.example", "Host: 127.0.0.1:\(port)"]] {
            let response = try Self.send(port: port, method: "POST",
                                         path: "/v1/chat/completions", headers: hosts)
            #expect(response.hasPrefix("HTTP/1.1 403"), "\(response.prefix(40))")
            #expect(response.contains("forbidden_host"))
        }
        try await server.shutdown()
    }

    @Test func loopbackNamesAndOriginsAreServed() async throws {
        let root = Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let unloads = UnloadCount()
        let server = Self.makeServer(root: root, unloads: unloads)
        let channel = try await server.start(port: 0)
        let port = try #require(channel.localAddress?.port)

        let accepted: [[String]] = [
            ["Host: 127.0.0.1:\(port)"],
            ["Host: 127.0.0.1"],
            ["Host: localhost:\(port)"],
            ["Host: LocalHost."],
            ["Host: [::1]:\(port)"],
            ["Host: 127.0.0.1:\(port)", "Origin: http://localhost:3000"],
            ["Host: 127.0.0.1:\(port)", "Origin: https://127.0.0.1"],
        ]
        for headers in accepted {
            let response = try Self.send(port: port, method: "POST",
                                         path: "/v1/chat/completions", headers: headers)
            #expect(response.hasPrefix("HTTP/1.1 200"), "\(headers)")
            #expect(response.contains(#""content":"ok""#), "\(headers)")
        }
        let status = try Self.send(port: port, method: "GET", path: ServerControl.statusPath,
                                   headers: ["Host: localhost:\(port)"])
        #expect(status.hasPrefix("HTTP/1.1 200"))
        let unload = try Self.send(port: port, method: "POST", path: ServerControl.unloadPath,
                                   headers: ["Host: 127.0.0.1:\(port)",
                                             "Authorization: Bearer \(Self.token)"])
        #expect(unload.hasPrefix("HTTP/1.1 200"))
        #expect(unloads.value == 1)

        // HTTP/1.0 has no Host requirement, and no browser sends it.
        let old = try Self.send(port: port, method: "POST", path: "/v1/chat/completions",
                                headers: [], version: "HTTP/1.0")
        #expect(old.hasPrefix("HTTP/1.1 200") || old.hasPrefix("HTTP/1.0 200"),
                "\(old.prefix(40))")
        #expect(old.contains(#""content":"ok""#))
        try await server.shutdown()
    }

    /// A refused request stages nothing, and the same connection still
    /// serves the next request.
    @Test func aRefusalStagesNothingAndKeepsTheConnectionUsable() async throws {
        let root = Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Self.makeServer(root: root, unloads: UnloadCount())
        let channel = try await server.start(port: 0)
        let port = try #require(channel.localAddress?.port)
        let socket = try connectedSocket(port: port)
        defer { _ = Darwin.close(socket) }

        let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let image = #"{"model":"test-model","messages":[{"role":"user","content":["#
            + #"{"type":"image_url","image_url":{"url":"data:image/png;base64,\#(pixel)"}}]}]}"#
        try writeAll(socket: socket, text: Self.request(
            method: "POST", path: "/v1/chat/completions",
            headers: ["Host: attacker.example:\(port)"], body: image,
            connection: "keep-alive"))
        let refused = try Self.readResponse(socket)
        #expect(refused.hasPrefix("HTTP/1.1 403"))
        #expect(Self.stagedFileCount(root) == 0)

        try writeAll(socket: socket, text: Self.request(
            method: "POST", path: "/v1/chat/completions",
            headers: ["Host: 127.0.0.1:\(port)"], body: Self.chatBody,
            connection: "keep-alive"))
        let served = try Self.readResponse(socket)
        #expect(served.hasPrefix("HTTP/1.1 200"))
        #expect(served.contains(#""content":"ok""#))
        try await server.shutdown()
    }
}
