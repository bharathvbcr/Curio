import Darwin
import Foundation

enum AgentSocketIO {
    static func openServer() -> Int32 {
        let path = AgentSocketPath.fileURL().path
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        guard setAddress(path, on: fd, bindSocket: true) else {
            close(fd)
            return -1
        }
        if listen(fd, 8) != 0 {
            close(fd)
            return -1
        }
        chmod(path, 0o600)
        return fd
    }

    static func openClient() -> Int32 {
        let path = AgentSocketPath.fileURL().path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        guard setAddress(path, on: fd, bindSocket: false) else {
            close(fd)
            return -1
        }
        return fd
    }

    static func writeLine(_ text: String, fd: Int32) {
        var line = text
        if !line.hasSuffix("\n") { line.append("\n") }
        _ = line.withCString { cstr in
            Darwin.write(fd, cstr, strlen(cstr))
        }
    }

    static func readLine(fd: Int32) -> String? {
        var buffer: [UInt8] = []
        var byte: UInt8 = 0
        while Darwin.read(fd, &byte, 1) == 1 {
            if byte == 10 { break }
            buffer.append(byte)
            if buffer.count > 8_000_000 { return nil }
        }
        if buffer.isEmpty { return nil }
        return String(bytes: buffer, encoding: .utf8)
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
