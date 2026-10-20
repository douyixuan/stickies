import Foundation
import Darwin

/// Bounded local connections. All mutations execute through the MainActor handler.
final class LocalCommandServer: @unchecked Sendable {
    private let directory: URL
    private let handler: @MainActor (SerializedNoteCommands.Request) throws -> SerializedNoteCommands.Result
    private let state = NSLock()
    private var active = true
    private var connections = Set<Int32>()
    private let listener: Int32
    private let endpoint: URL

    @MainActor init(directory: URL,
                    handler: @escaping @MainActor (SerializedNoteCommands.Request) throws -> SerializedNoteCommands.Result) throws {
        try LocalCommandSocket.inspectDirectory(directory)
        let endpoint = directory.appendingPathComponent(LocalCommandSocket.filename)
        if try LocalCommandSocket.inspectEndpoint(endpoint) { try FileManager.default.removeItem(at: endpoint) }
        var address = try LocalCommandSocket.address(directory)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalCommandSocket.Failure.unavailable }
        LocalCommandSocket.configure(fd, timeout: 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw LocalCommandSocket.Failure.unavailable }
        guard chmod(endpoint.path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd); unlink(endpoint.path); throw LocalCommandSocket.Failure.unavailable
        }
        self.directory = directory
        self.handler = handler
        self.listener = fd
        self.endpoint = endpoint
        DispatchQueue.global(qos: .utility).async { self.acceptConnections() }
    }
    private func acceptConnections() {
        defer { close(listener) }
        while true {
            state.lock(); let running = active; state.unlock()
            if !running { return }
            let fd = accept(listener, nil, nil)
            if fd < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                return
            }
            LocalCommandSocket.configure(fd)
            state.lock()
            let accepted = active && connections.count < 8 && LocalCommandSocket.sameUser(fd)
            if accepted { connections.insert(fd) }
            state.unlock()
            if !accepted { close(fd); continue }
            DispatchQueue.global(qos: .utility).async { self.receive(fd) }
        }
    }
    private func receive(_ fd: Int32) {
        do {
            let message = try JSONDecoder().decode(LocalCommandSocket.Message.self, from: LocalCommandSocket.readFrame(fd))
            guard message.version == 1 else { throw LocalCommandSocket.Failure.invalidFrame }
            Task { @MainActor in
                let running = self.state.withLock { self.active }
                guard running else {
                    self.respond(.init(code: "unavailable", message: "The application is stopping. No command was accepted.", status: 75), to: fd)
                    return
                }
                let reply: LocalCommandSocket.Reply
                do { reply = .init(result: try self.handler(message.request)) }
                catch let failure as SerializedNoteCommands.Failure {
                    let code: String
                    let status: Int32
                    switch failure {
                    case .notFound: code = "not_found"; status = 66
                    case .invalidRequest: code = "usage"; status = 64
                    case .conflictingRequestID: code = "request_conflict"; status = 64
                    case .recoveryRequired: code = "recovery_required"; status = 75
                    case .ledgerFull: code = "capacity"; status = 75
                    default: code = "invalid_data"; status = 65
                    }
                    reply = .init(code: code, message: "The command could not complete. Preserve its request ID before retrying.", status: status)
                } catch {
                    reply = .init(code: "outcome_unknown", message: "Storage failed. Query or retry the same request ID after recovery.", status: 74)
                }
                self.respond(reply, to: fd)
            }
        } catch {
            respond(.init(code: "usage", message: "Invalid or incomplete local request. No command was accepted.", status: 64), to: fd)
        }
    }
    private func respond(_ reply: LocalCommandSocket.Reply, to fd: Int32) {
        DispatchQueue.global(qos: .utility).async {
            defer { self.finish(fd) }
            do {
                let data = try SerializedNoteCommands.encoded(reply)
                if data.count > LocalCommandSocket.maximumFrame {
                    let failure = LocalCommandSocket.Reply(code: "outcome_unknown", message: "The response exceeds the local transport limit. Preserve the request ID.", status: 74)
                    try LocalCommandSocket.writeFrame(SerializedNoteCommands.encoded(failure), to: fd)
                } else { try LocalCommandSocket.writeFrame(data, to: fd) }
            } catch { /* A disconnected client can query the durable request result. */ }
        }
    }
    private func finish(_ fd: Int32) {
        state.lock()
        connections.remove(fd)
        close(fd)
        state.unlock()
    }
    @MainActor func stop() {
        state.lock()
        guard active else { state.unlock(); return }
        active = false
        _ = shutdown(listener, SHUT_RDWR)
        for fd in connections { _ = shutdown(fd, SHUT_RDWR) }
        state.unlock()
        // The App still owns notes.lock here. No replacement server can bind yet.
        try? FileManager.default.removeItem(at: endpoint)
    }
}
