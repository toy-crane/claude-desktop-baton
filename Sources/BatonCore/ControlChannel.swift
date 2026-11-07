import Darwin
import Foundation

/// The local socket the menu bar app listens on for switches asked for on the command line.
/// One JSON line in; one or two JSON lines back (accepted, then done; or refused).
/// Only processes of the same user may connect: the socket file is private and the peer is checked.
public final class ControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ControlRequest, ControlReply) -> Void

    private let path: String
    private let source: DispatchSourceRead

    public init(socket: URL, handler: @escaping Handler) throws {
        path = socket.path
        try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // Another running copy of the app keeps its socket; a file left by one that quit is replaced.
        if ControlClient.isListening(socket) { throw BatonError("Another Claude Desktop Baton is already listening.") }
        unlink(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BatonError("The control socket could not be created.") }
        guard var address = UnixAddress.make(path) else {
            close(fd)
            throw BatonError("The control socket path is too long.")
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd)
            unlink(path)
            throw BatonError("The control socket could not be opened.")
        }

        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "baton.control"))
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            ControlServer.serve(client, handler: handler)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { stop() }

    public func stop() {
        guard !source.isCancelled else { return }
        source.cancel()
        unlink(path)
    }

    private static func serve(_ client: Int32, handler: @escaping Handler) {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); return }
        Socket.configure(client, timeout: 5)
        DispatchQueue.global().async {
            var reader = LineReader(fd: client)
            guard case .line(let line) = reader.next(),
                  let request = try? JSONDecoder().decode(ControlRequest.self, from: line) else { close(client); return }
            handler(request, ControlReply(fd: client))
        }
    }
}

/// Answers one request. A refusal or the outcome ends it. Writes to a caller that went away are ignored,
/// so the switch carries on without it.
public final class ControlReply: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32?

    init(fd: Int32) { self.fd = fd }
    deinit { if let fd { close(fd) } }

    public func send(_ response: ControlResponse) {
        lock.lock(); defer { lock.unlock() }
        guard let fd, var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        Socket.writeAll(fd, data)
        if response.event != .accepted {
            close(fd)
            self.fd = nil
        }
    }
}

public enum ControlClient {
    /// Whether a menu bar app is listening.
    public static func isListening(_ socket: URL) -> Bool {
        guard let fd = connect(socket) else { return false }
        close(fd)
        return true
    }

    /// Sends a request; with `wait`, returns the final response, otherwise the first.
    public static func send(_ request: ControlRequest, socket: URL, wait: Bool, timeout: TimeInterval) throws(ControlError) -> ControlResponse {
        guard let fd = connect(socket) else { throw .unreachable }
        defer { close(fd) }
        guard var data = try? JSONEncoder().encode(request) else { throw .broken("The request could not be encoded.") }
        data.append(0x0A)
        Socket.configure(fd, timeout: timeout)
        guard Socket.writeAll(fd, data) else { throw .broken("The menu bar app closed the connection.") }

        let deadline = Date().addingTimeInterval(timeout)
        var reader = LineReader(fd: fd)
        while true {
            Socket.setReceiveTimeout(fd, max(0.01, deadline.timeIntervalSinceNow))
            switch reader.next() {
            case .line(let line):
                guard let response = try? JSONDecoder().decode(ControlResponse.self, from: line) else {
                    throw .broken("The menu bar app sent an answer this command does not understand.")
                }
                if !wait || response.event != .accepted { return response }
            case .timedOut:
                throw .timedOut
            case .closed:
                throw .broken("The menu bar app closed the connection before answering.")
            }
        }
    }

    private static func connect(_ socket: URL) -> Int32? {
        guard var address = UnixAddress.make(socket.path) else { return nil }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(fd); return nil }
        return fd
    }
}

// MARK: socket plumbing

enum UnixAddress {
    static func make(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
        }
        return address
    }
}

enum Socket {
    /// No SIGPIPE when the other side is gone, and a bounded wait for reads.
    static func configure(_ fd: Int32, timeout: TimeInterval) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setReceiveTimeout(fd, timeout)
    }

    static func setReceiveTimeout(_ fd: Int32, _ seconds: TimeInterval) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }
}

struct LineReader {
    enum Next { case line(Data), timedOut, closed }
    let fd: Int32
    private var buffer = Data()
    init(fd: Int32) { self.fd = fd }

    mutating func next() -> Next {
        while true {
            if let end = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<end]
                buffer = Data(buffer[buffer.index(after: end)...])
                return .line(Data(line))
            }
            guard buffer.count < 1 << 16 else { return .closed }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = read(fd, &chunk, chunk.count)
            if count > 0 { buffer.append(contentsOf: chunk[0..<count]); continue }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return .timedOut }
            return .closed
        }
    }
}
