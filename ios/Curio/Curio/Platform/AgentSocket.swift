import Darwin
import Foundation

enum AgentSocketIO {
    /// Listen backlog. Enough for a burst of agent clients without refusing the handshake.
    static let listenBacklog: Int32 = 128

    static func openServer(at url: URL = AgentSocketPath.fileURL()) -> Int32 {
        let path = url.path
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        configure(fd)
        guard setAddress(path, on: fd, bindSocket: true) else {
            close(fd)
            return -1
        }
        if listen(fd, listenBacklog) != 0 {
            close(fd)
            return -1
        }
        chmod(path, 0o600)
        return fd
    }

    static func openClient(at url: URL = AgentSocketPath.fileURL()) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        configure(fd)
        guard setAddress(url.path, on: fd, bindSocket: false) else {
            close(fd)
            return -1
        }
        return fd
    }

    /// Writes the whole line. A closed peer returns false instead of raising SIGPIPE.
    @discardableResult
    static func writeLine(_ text: String, fd: Int32) -> Bool {
        var bytes = Array(text.utf8)
        if bytes.last != 10 { bytes.append(10) }
        var offset = 0
        while offset < bytes.count {
            let written: ssize_t = bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            }
            if written > 0 {
                offset += written
                continue
            }
            if written < 0 && errno == EINTR { continue }
            return false
        }
        return true
    }

    /// One newline-delimited message. A line past `maxBytes` is discarded and consumed,
    /// so the next call still starts on a message boundary.
    static func readLine(fd: Int32, maxBytes: Int = 8_000_000) -> String? {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(256)
        var byte: UInt8 = 0
        var overflow = false
        while true {
            let n = Darwin.read(fd, &byte, 1)
            if n == 1 {
                if byte == 10 { break }
                if overflow { continue }
                buffer.append(byte)
                if buffer.count > maxBytes {
                    overflow = true
                    buffer.removeAll(keepingCapacity: false)
                }
                continue
            }
            if n < 0 && errno == EINTR { continue }
            if overflow || buffer.isEmpty { return nil }
            return String(bytes: buffer, encoding: .utf8)
        }
        if overflow || buffer.isEmpty { return nil }
        return String(bytes: buffer, encoding: .utf8)
    }

    /// `SO_NOSIGPIPE` keeps a dropped agent from killing the process. `FD_CLOEXEC` keeps the
    /// socket out of children this process launches.
    private static func configure(_ fd: Int32) {
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFD)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC)
        }
    }

    private static func setAddress(_ path: String, on fd: Int32, bindSocket: Bool) -> Bool {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return false }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { rebound in
                _ = path.withCString { strncpy(rebound, $0, capacity - 1) }
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                bindSocket ? Darwin.bind(fd, rebound, length) : Darwin.connect(fd, rebound, length)
            }
        }
        return result == 0
    }
}
