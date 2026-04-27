//
//  HookSocketServer.swift
//  VibePulse
//
//  Unix domain socket server for real-time hook events
//  Adapted from Vibe Notch: changed socket path, extended HookEvent with bash fields
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "Hooks")

/// Event received from Claude Code hooks (extended with bash output fields)
struct HookEvent: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?

    // Vibe Pulse extensions: Bash tool output capture
    let stdout: String?
    let stderr: String?
    let exitCode: Int?
    let bashCommand: String?
    let toolError: String?
    let stopError: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd, event, status, pid, tty, tool
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case message, stdout, stderr
        case exitCode = "exit_code"
        case bashCommand = "bash_command"
        case toolError = "tool_error"
        case stopError = "stop_error"
    }

    var sessionPhase: SessionPhase {
        if event == "PreCompact" {
            return .compacting
        }

        switch status {
        case "waiting_for_approval":
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool ?? "unknown",
                toolInput: toolInput,
                receivedAt: Date()
            ))
        case "waiting_for_input":
            return .waitingForInput
        case "running_tool", "processing", "starting":
            return .processing
        case "compacting":
            return .compacting
        case "ended":
            return .ended
        default:
            return .idle
        }
    }

    nonisolated var expectsResponse: Bool {
        event == "PermissionRequest" && status == "waiting_for_approval"
    }
}

typealias HookEventHandler = @Sendable (HookEvent) -> Void

/// Unix domain socket server for hook events
class HookSocketServer {
    nonisolated(unsafe) static let shared = HookSocketServer()
    static let socketPath = "/tmp/claude-pulse.sock"

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var eventHandler: HookEventHandler?
    private let queue = DispatchQueue(label: "com.vibepulse.socket", qos: .userInitiated)

    private var toolUseIdCache: [String: [String]] = [:]
    private let cacheLock = NSLock()

    /// Pending permission sockets: toolUseId -> (file descriptor, received time)
    private var pendingPermissions: [String: (fd: Int32, receivedAt: Date)] = [:]
    private let permissionLock = NSLock()
    private static let permissionTimeout: TimeInterval = 290  // Just under Python's 300s

    private init() {}

    func start(onEvent: @escaping HookEventHandler) {
        queue.async { [weak self] in
            self?.startServer(onEvent: onEvent)
        }
    }

    private func startServer(onEvent: @escaping HookEventHandler) {
        guard serverSocket < 0 else { return }

        eventHandler = onEvent
        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        chmod(Self.socketPath, 0o600)

        guard listen(serverSocket, 10) == 0 else {
            logger.error("Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        logger.info("Listening on \(Self.socketPath, privacy: .public)")

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        acceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
                self?.serverSocket = -1
            }
        }
        acceptSource?.resume()
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        closeAllPendingPermissions()
        unlink(Self.socketPath)
    }

    // MARK: - Permission Response

    /// Send an allow/deny response back to the hook script for a pending permission request.
    func sendPermissionResponse(toolUseId: String, decision: String, reason: String = "") {
        permissionLock.lock()
        guard let entry = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionLock.unlock()
            logger.warning("No pending permission for toolUseId \(toolUseId.prefix(16), privacy: .public)")
            return
        }
        permissionLock.unlock()

        let response: [String: String] = ["decision": decision, "reason": reason]
        if let data = try? JSONSerialization.data(withJSONObject: response),
           let json = String(data: data, encoding: .utf8) {
            json.withCString { ptr in
                let len = strlen(ptr)
                _ = write(entry.fd, ptr, len)
            }
            logger.info("Sent \(decision, privacy: .public) for toolUseId \(toolUseId.prefix(16), privacy: .public)")
        }

        close(entry.fd)
    }

    /// Close a pending permission socket without sending a response.
    /// The hook script will get an empty recv and fall through to terminal behavior.
    func closePendingPermission(toolUseId: String) {
        permissionLock.lock()
        guard let entry = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionLock.unlock()
            return
        }
        permissionLock.unlock()
        close(entry.fd)
        logger.info("Closed pending permission (suppressed) for \(toolUseId.prefix(16), privacy: .public)")
    }

    private func holdSocketForPermission(toolUseId: String, clientSocket: Int32) {
        permissionLock.lock()
        pendingPermissions[toolUseId] = (fd: clientSocket, receivedAt: Date())
        permissionLock.unlock()

        // Schedule cleanup for stale sockets
        queue.asyncAfter(deadline: .now() + Self.permissionTimeout) { [weak self] in
            self?.cleanupStalePermission(toolUseId: toolUseId)
        }
    }

    private func cleanupStalePermission(toolUseId: String) {
        permissionLock.lock()
        guard let entry = pendingPermissions[toolUseId] else {
            permissionLock.unlock()
            return
        }
        let age = Date().timeIntervalSince(entry.receivedAt)
        if age >= Self.permissionTimeout {
            pendingPermissions.removeValue(forKey: toolUseId)
            permissionLock.unlock()
            close(entry.fd)
            logger.info("Cleaned up stale permission socket for \(toolUseId.prefix(16), privacy: .public)")
        } else {
            permissionLock.unlock()
        }
    }

    private func closeAllPendingPermissions() {
        permissionLock.lock()
        for (_, entry) in pendingPermissions {
            close(entry.fd)
        }
        pendingPermissions.removeAll()
        permissionLock.unlock()
    }

    // MARK: - Tool Use ID Cache

    private static let sortedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private func cacheKey(sessionId: String, toolName: String?, toolInput: [String: AnyCodable]?) -> String {
        let inputStr: String
        if let input = toolInput,
           let data = try? Self.sortedEncoder.encode(input),
           let str = String(data: data, encoding: .utf8) {
            inputStr = str
        } else {
            inputStr = "{}"
        }
        return "\(sessionId):\(toolName ?? "unknown"):\(inputStr)"
    }

    private func cacheToolUseId(event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        if toolUseIdCache[key] == nil {
            toolUseIdCache[key] = []
        }
        toolUseIdCache[key]?.append(toolUseId)
        cacheLock.unlock()
    }

    private func popCachedToolUseId(event: HookEvent) -> String? {
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard var queue = toolUseIdCache[key], !queue.isEmpty else { return nil }
        let toolUseId = queue.removeFirst()
        if queue.isEmpty {
            toolUseIdCache.removeValue(forKey: key)
        } else {
            toolUseIdCache[key] = queue
        }
        return toolUseId
    }

    private func cleanupCache(sessionId: String) {
        cacheLock.lock()
        let keysToRemove = toolUseIdCache.keys.filter { $0.hasPrefix("\(sessionId):") }
        for key in keysToRemove {
            toolUseIdCache.removeValue(forKey: key)
        }
        cacheLock.unlock()
    }

    // MARK: - Private

    private func acceptConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 131072)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 0.5 {
            let pollResult = poll(&pollFd, 1, 50)
            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                if bytesRead > 0 {
                    allData.append(contentsOf: buffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    break
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
            } else if pollResult == 0 {
                if !allData.isEmpty { break }
            } else {
                break
            }
        }

        guard !allData.isEmpty else {
            close(clientSocket)
            return
        }

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: allData) else {
            logger.warning("Failed to parse event")
            close(clientSocket)
            return
        }

        logger.debug("Received: \(event.event, privacy: .public) for \(event.sessionId.prefix(8), privacy: .public)")

        if event.event == "PreToolUse" {
            cacheToolUseId(event: event)
        }

        if event.event == "SessionEnd" {
            cleanupCache(sessionId: event.sessionId)
        }

        // For permission requests, hold the socket open so we can send back allow/deny.
        // For all other events, close immediately.
        if event.expectsResponse, let toolUseId = event.toolUseId, !toolUseId.isEmpty {
            holdSocketForPermission(toolUseId: toolUseId, clientSocket: clientSocket)
        } else {
            close(clientSocket)
        }

        eventHandler?(event)
    }

}

// MARK: - AnyCodable

struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated(unsafe) let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}
