import Foundation
import Darwin

/// Local AF_UNIX transport only. The server owns notes.lock for its whole lifetime.
enum LocalCommandSocket {
    static let filename = "istk.sock"
    static let maximumFrame = 16 * 1024 * 1024
    struct Message: Codable {
        var version = 1
        var request: SerializedNoteCommands.Request
    }
    struct Reply: Codable {
        var version = 1
        var result: SerializedNoteCommands.Result?
        var code: String?
        var message: String?
        var status: Int32?
    }
    enum Failure: Error { case unavailable, unsafeEndpoint, tooLarge, disconnected, timeout, invalidFrame }

    static func address(_ directory: URL) throws -> sockaddr_un {
        let path = directory.appendingPathComponent(filename).path
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.unavailable }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        return address
    }
    static func configure(_ fd: Int32, timeout: Int = 5) {
        var interval = timeval(tv_sec: timeout, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }
    static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == geteuid()
    }
    static func inspectDirectory(_ directory: URL) throws {
        var info = stat()
        guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o022 == 0 else { throw Failure.unsafeEndpoint }
    }
    static func inspectEndpoint(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return false }
            throw Failure.unsafeEndpoint
        }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0, info.st_nlink == 1 else { throw Failure.unsafeEndpoint }
        return true
    }
    static func deadline() -> UInt64 { DispatchTime.now().uptimeNanoseconds + 5_000_000_000 }
    static func waitReady(_ fd: Int32, events: Int16, until deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw Failure.timeout }
            let milliseconds = Int32(min((deadline - now + 999_999) / 1_000_000, UInt64(Int32.max)))
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let status = poll(&descriptor, 1, milliseconds)
            if status < 0 && errno == EINTR { continue }
            if status == 0 { throw Failure.timeout }
            guard status > 0 else { throw Failure.disconnected }
            if descriptor.revents & events != 0 { return }
            throw Failure.disconnected
        }
    }
    static func readExactly(_ fd: Int32, count: Int, deadline: UInt64) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                try waitReady(fd, events: Int16(POLLIN), until: deadline)
                let length = recv(fd, buffer.baseAddress!.advanced(by: offset), count - offset, MSG_DONTWAIT)
                if length < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
                guard length > 0 else {
                    if errno == EAGAIN || errno == EWOULDBLOCK { throw Failure.timeout }
                    throw Failure.disconnected
                }
                offset += length
            }
        }
        return data
    }
    static func readFrame(_ fd: Int32) throws -> Data {
        let deadline = deadline()
        let header = try readExactly(fd, count: 4, deadline: deadline)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maximumFrame else { throw Failure.tooLarge }
        return try readExactly(fd, count: Int(length), deadline: deadline)
    }
    static func writeFrame(_ data: Data, to fd: Int32) throws {
        guard !data.isEmpty, data.count <= maximumFrame else { throw Failure.tooLarge }
        var length = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(data)
        let deadline = deadline()
        try frame.withUnsafeBytes { buffer in
            var offset = 0
            while offset < frame.count {
                try waitReady(fd, events: Int16(POLLOUT), until: deadline)
                let sent = send(fd, buffer.baseAddress!.advanced(by: offset), frame.count - offset, MSG_DONTWAIT)
                if sent < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
                guard sent > 0 else { throw Failure.disconnected }
                offset += sent
            }
        }
    }
    static func connect(to directory: URL) throws -> Int32 {
        try inspectDirectory(directory)
        guard try inspectEndpoint(directory.appendingPathComponent(filename)) else { throw Failure.unavailable }
        var endpoint = try address(directory)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.unavailable }
        configure(fd)
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let status = withUnsafePointer(to: &endpoint) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        do {
            if status != 0 {
                guard errno == EINPROGRESS || errno == EAGAIN else { throw Failure.unavailable }
                try waitReady(fd, events: Int16(POLLOUT), until: deadline())
                var error: Int32 = 0
                var size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw Failure.unavailable }
            }
            guard sameUser(fd) else { throw Failure.unsafeEndpoint }
        } catch { close(fd); throw error }
        return fd
    }
}
