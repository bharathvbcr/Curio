#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

enum AgentSocketIO {
    /// Listen backlog. Enough for a burst of agent clients without refusing the handshake.
    static let listenBacklog: Int32 = 128

    /// Binds a fresh listening socket at `url`. A socket file that still answers belongs to a
    /// live Curio, so it is left alone and this returns -1 instead of stealing it.
    static func openServer(at url: URL = AgentSocketPath.fileURL()) -> Int32 {
        let path = url.path
        if isLive(path) { return -1 }
        unlink(path)
        let fd = socket(AF_UNIX, streamType, 0)
        guard fd >= 0 else { return -1 }
        configure(fd)
        guard setAddress(path, on: fd, bindSocket: true) else {
            close(fd)
            return -1
        }
        chmod(path, 0o600)
        if listen(fd, listenBacklog) != 0 {
            close(fd)
            unlink(path)
            return -1
        }
        return fd
    }

    static func openClient(at url: URL = AgentSocketPath.fileURL()) -> Int32 {
        let fd = socket(AF_UNIX, streamType, 0)
        guard fd >= 0 else { return -1 }
        configure(fd)
        guard setAddress(url.path, on: fd, bindSocket: false) else {
            close(fd)
            return -1
        }
        return fd
    }

    /// Applies the same no-SIGPIPE and close-on-exec settings to a descriptor from `accept`.
    static func prepareAccepted(_ fd: Int32) {
        configure(fd)
    }

    /// Bounds blocking reads and writes on `fd`. A peer that stalls past the limit makes
    /// `readLine` return nil and `writeLine` return false instead of holding the thread.
    static func setTimeouts(_ fd: Int32, read: TimeInterval, write: TimeInterval) {
        func apply(_ seconds: TimeInterval, _ option: Int32) {
            guard seconds > 0 else { return }
            let whole = Int(seconds)
            let micros = Int((seconds - Double(whole)) * 1_000_000)
            var value = timeval()
            value.tv_sec = .init(whole)
            value.tv_usec = .init(micros)
            _ = setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
        }
        apply(read, SO_RCVTIMEO)
        apply(write, SO_SNDTIMEO)
    }

    /// Writes the whole line. A closed peer returns false instead of raising SIGPIPE.
    @discardableResult
    static func writeLine(_ text: String, fd: Int32) -> Bool {
        var bytes = Array(text.utf8)
        if bytes.last != 10 { bytes.append(10) }
        var offset = 0
        while offset < bytes.count {
            let written: Int = bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return -1 }
                return send(fd, base.advanced(by: offset), bytes.count - offset, sendFlags)
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
    /// so the next call still starts on a message boundary. Bytes after the newline stay
    /// in the socket for the next call. Invalid UTF-8, a timeout, or EOF before any byte is nil.
    static func readLine(fd: Int32, maxBytes: Int = 8_000_000) -> String? {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(256)
        var overflow = false
        var chunk = [UInt8](repeating: 0, count: 4096)
        var canPeek = true
        while true {
            // Peek first so the read stops exactly at the newline; fall back to single bytes
            // when `fd` is not a socket.
            var take = 1
            if canPeek {
                let peeked = chunk.withUnsafeMutableBytes { raw in
                    recv(fd, raw.baseAddress, raw.count, Int32(MSG_PEEK))
                }
                if peeked > 0 {
                    if let newline = chunk[0..<peeked].firstIndex(of: 10) {
                        take = newline + 1
                    } else {
                        take = peeked
                    }
                } else if peeked < 0 && errno == ENOTSOCK {
                    canPeek = false
                } else if peeked < 0 && errno == EINTR {
                    continue
                } else {
                    // EOF, timeout, or a dead socket.
                    break
                }
            }
            let n = chunk.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress, take)
            }
            if n > 0 {
                var sawNewline = false
                for byte in chunk[0..<n] {
                    if byte == 10 {
                        sawNewline = true
                        break
                    }
                    if overflow { continue }
                    buffer.append(byte)
                    if buffer.count > maxBytes {
                        overflow = true
                        buffer.removeAll(keepingCapacity: false)
                    }
                }
                if sawNewline { break }
                continue
            }
            if n < 0 && errno == EINTR { continue }
            break
        }
        if overflow || buffer.isEmpty { return nil }
        return String(validating: buffer, as: UTF8.self)
    }

    /// True when something is accepting connections at `path` right now.
    static func isLive(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return false }
        let fd = socket(AF_UNIX, streamType, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        configure(fd)
        setTimeouts(fd, read: 1, write: 1)
        return setAddress(path, on: fd, bindSocket: false)
    }

    #if canImport(Darwin)
    private static let streamType = SOCK_STREAM
    private static let sendFlags: Int32 = 0
    #else
    private static let streamType = Int32(SOCK_STREAM.rawValue)
    private static let sendFlags = Int32(MSG_NOSIGNAL)
    #endif

    /// `SO_NOSIGPIPE` (or `MSG_NOSIGNAL` on Linux) keeps a dropped agent from killing the
    /// process. `FD_CLOEXEC` keeps the socket out of children this process launches.
    private static func configure(_ fd: Int32) {
        #if canImport(Darwin)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
        let flags = fcntl(fd, F_GETFD)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC)
        }
    }

    private static func setAddress(_ path: String, on fd: Int32, bindSocket: Bool) -> Bool {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !path.isEmpty, path.utf8.count < capacity, !path.utf8.contains(0) else { return false }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { rebound in
                _ = path.withCString { strncpy(rebound, $0, capacity - 1) }
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                bindSocket ? bind(fd, rebound, length) : connect(fd, rebound, length)
            }
        }
        return result == 0
    }
}
