import Darwin
import XCTest

@testable import NostrChatBar

final class ControlCommandDecoderTests: XCTestCase {
    func testDecodesPanelCommands() {
        XCTAssertEqual(ControlCommandDecoder.decode(line: #"{"cmd":"toggle"}"#), .toggle)
        XCTAssertEqual(ControlCommandDecoder.decode(line: #"{"cmd":"present"}"#), .present)
        XCTAssertEqual(ControlCommandDecoder.decode(line: #"{"cmd":"hide"}"#), .hide)
    }

    func testIgnoresExtraFields() {
        XCTAssertEqual(
            ControlCommandDecoder.decode(line: #"{"cmd":"toggle","path":"/etc/passwd"}"#),
            .toggle)
    }

    func testRejectsUnknownAndMalformedInput() {
        for line in [
            #"{"cmd":"send","text":"hi"}"#,  // message commands belong to the daemon socket
            #"{"cmd":"quit"}"#,
            #"{"cmd":42}"#,
            #"{}"#,
            "toggle",
            "{",
            "",
        ] {
            XCTAssertNil(ControlCommandDecoder.decode(line: line), line)
        }
    }
}

final class ControlSocketServerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func socketPath(_ name: String = "ctl.sock") -> String {
        dir.appendingPathComponent(name).path
    }

    private func connect(to path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            path.utf8CString.withUnsafeBytes { source in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: source.prefix(raw.count)))
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, size)
            }
        }
        XCTAssertEqual(connected, 0, "connect \(path)")
        return fd
    }

    func testBindsWithOwnerOnlyPermissions() throws {
        let server = ControlSocketServer(path: socketPath())
        defer { server.stop() }
        try server.start()

        var status = stat()
        XCTAssertEqual(lstat(socketPath(), &status), 0)
        XCTAssertEqual(status.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(status.st_mode & 0o777, 0o600)
    }

    func testRefusesNonSocketPath() throws {
        let path = socketPath("occupied")
        try Data("not a socket".utf8).write(to: URL(fileURLWithPath: path))
        let server = ControlSocketServer(path: path)
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(
                error as? ControlSocketServer.Failure, .pathOccupied(path))
        }
        // The occupying file survives the refusal.
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testReplacesStaleSocket() throws {
        let path = socketPath()
        let first = ControlSocketServer(path: path)
        try first.start()
        first.stop()

        // Simulate a crash leaving the file behind.
        let again = ControlSocketServer(path: path)
        defer { again.stop() }
        try again.start()
        var status = stat()
        XCTAssertEqual(lstat(path, &status), 0)
        XCTAssertEqual(status.st_mode & S_IFMT, S_IFSOCK)
    }

    func testDeliversValidCommandsAndIgnoresGarbage() throws {
        let server = ControlSocketServer(path: socketPath())
        defer { server.stop() }
        let received = expectation(description: "command delivered")
        var commands: [ControlCommand] = []
        server.onCommand = { command in
            commands.append(command)
            if commands.count == 2 { received.fulfill() }
        }
        try server.start()

        let client = connect(to: socketPath())
        defer { close(client) }
        let payload = "not json\n{\"cmd\":\"quit\"}\n{\"cmd\":\"toggle\"}\n{\"cmd\":\"hide\"}\n"
        payload.utf8CString.withUnsafeBufferPointer { pointer in
            _ = write(client, pointer.baseAddress, pointer.count - 1)
        }

        wait(for: [received], timeout: 5)
        XCTAssertEqual(commands, [.toggle, .hide])
    }
}
