import Darwin
import Foundation

// MARK: - Control socket
//
// UI-level IPC: a second unix socket owned by the bar for panel
// commands only. Message-level operations (send, send-file, retry,
// cancel) already have an IPC surface — the daemon socket — so this
// carries nothing but window intent.

enum ControlCommand: String {
    case toggle
    case present
    case hide
}

enum ControlCommandDecoder {
    /// One NDJSON line → command. Anything malformed or unknown is nil;
    /// the caller logs and drops it.
    static func decode(line: String) -> ControlCommand? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let cmd = dict["cmd"] as? String
        else { return nil }
        return ControlCommand(rawValue: cmd)
    }
}

/// POSIX listener rather than Network.framework: the socket file's
/// permissions are the authentication, so mode 0600 must be
/// deterministic.
final class ControlSocketServer {
    enum Failure: Error, Equatable {
        /// Path exists and is not a socket — refuse to unlink a regular
        /// file, directory, or symlink someone parked there.
        case pathOccupied(String)
        case pathTooLong(String)
        case systemCall(String)
    }

    private final class Connection {
        let source: DispatchSourceRead
        var buffer: [UInt8] = []
        init(source: DispatchSourceRead) { self.source = source }
    }

    private let path: String
    private let queue = DispatchQueue(label: "io.mulatta.nostr-chat-bar.control")
    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    /// Delivered on the main queue.
    var onCommand: ((ControlCommand) -> Void)?

    init(path: String) {
        self.path = path
    }

    deinit { stop() }

    /// Removes a stale socket at `path`; refuses to touch anything else.
    static func prepare(path: String) throws {
        var status = stat()
        guard lstat(path, &status) == 0 else { return }
        guard (status.st_mode & S_IFMT) == S_IFSOCK else {
            throw Failure.pathOccupied(path)
        }
        unlink(path)
    }

    func start() throws {
        try Self.prepare(path: path)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path) - 1
        guard path.utf8.count <= capacity else { throw Failure.pathTooLong(path) }

        // Darwin.socket explicitly: main.swift's top-level `socket`
        // variable shadows the libc function module-wide.
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.systemCall("socket") }

        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            path.utf8CString.withUnsafeBytes { source in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: source.prefix(raw.count)))
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, size)
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 4) == 0 else {
            close(fd)
            unlink(path)
            throw Failure.systemCall("bind/listen")
        }

        listenerFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.setCancelHandler { close(fd) }
        acceptSource = source
        source.resume()
    }

    func stop() {
        queue.sync {
            for (fd, connection) in connections {
                connection.source.cancel()
                _ = fd  // closed by the cancel handler
            }
            connections.removeAll()
            acceptSource?.cancel()
            acceptSource = nil
            if listenerFD >= 0 {
                listenerFD = -1
                unlink(path)
            }
        }
    }

    private func acceptClient() {
        let client = accept(listenerFD, nil, nil)
        guard client >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
        let connection = Connection(source: source)
        source.setEventHandler { [weak self] in self?.readClient(client) }
        source.setCancelHandler { close(client) }
        connections[client] = connection
        source.resume()
    }

    private func readClient(_ client: Int32) {
        guard let connection = connections[client] else { return }
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &chunk, chunk.count)
        guard count > 0 else {
            dropClient(client)
            return
        }
        connection.buffer.append(contentsOf: chunk[0..<count])
        while let newline = connection.buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: connection.buffer[..<newline], as: UTF8.self)
            connection.buffer.removeSubrange(...newline)
            dispatch(line: line)
        }
        // A client that never sends a newline doesn't get to grow memory.
        if connection.buffer.count > 64 * 1024 { dropClient(client) }
    }

    private func dispatch(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let command = ControlCommandDecoder.decode(line: trimmed) else {
            FileHandle.standardError.write(
                Data("nostr-chat-bar: ignoring control input: \(trimmed.prefix(120))\n".utf8))
            return
        }
        DispatchQueue.main.async { [weak self] in self?.onCommand?(command) }
    }

    private func dropClient(_ client: Int32) {
        connections.removeValue(forKey: client)?.source.cancel()
    }
}
