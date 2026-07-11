import Foundation
import Network

// MARK: - Daemon socket

/// Persistent NDJSON unix socket. Auto-reconnects with capped backoff
/// and fires `onConnect` so the owner can issue a replay — that's the
/// whole resync protocol, identical to Main.qml's Loader<Socket>.
final class Daemon {
    var onEvent: ((Event) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    private let path: String
    private var conn: NWConnection?
    private var buf = Data()
    private var backoff: TimeInterval = 0.5
    private let q = DispatchQueue(label: "nostr-chatd.sock")

    init(path: String) { self.path = path }

    func start() { connect() }

    func send(_ obj: [String: Any]) {
        guard let c = conn, c.state == .ready,
              var data = try? JSONSerialization.data(withJSONObject: obj)
        else { return }
        data.append(0x0a)
        c.send(content: data, completion: .contentProcessed { _ in })
    }

    private func connect() {
        let ep = NWEndpoint.unix(path: path)
        let c = NWConnection(to: ep, using: .tcp)
        conn = c
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.backoff = 0.5
                DispatchQueue.main.async { self.onConnect?() }
                self.receive()
            case .failed, .cancelled:
                DispatchQueue.main.async { self.onDisconnect?() }
                self.scheduleReconnect()
            default: break
            }
        }
        c.start(queue: q)
    }

    private func scheduleReconnect() {
        // Both the state handler (.failed/.cancelled) and receive's
        // eof/err path can land here for the same connection — and
        // cancel() below itself triggers .cancelled. Gate on conn so
        // only the first caller schedules the timer.
        guard conn != nil else { return }
        conn?.cancel(); conn = nil; buf.removeAll()
        let d = backoff
        backoff = min(backoff * 2, 4.0)  // under daemon's RestartSec=5
        q.asyncAfter(deadline: .now() + d) { [weak self] in self?.connect() }
    }

    private func receive() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, eof, err in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buf.append(data)
                self.drain()
            }
            if eof || err != nil {
                DispatchQueue.main.async { self.onDisconnect?() }
                self.scheduleReconnect()
                return
            }
            self.receive()
        }
    }

    private func drain() {
        while let nl = buf.firstIndex(of: 0x0a) {
            let line = buf.subdata(in: buf.startIndex..<nl)
            buf.removeSubrange(buf.startIndex...nl)
            guard let ev = try? JSONDecoder().decode(Event.self, from: line) else {
                FileHandle.standardError.write(Data("bad ipc json: \(String(decoding: line, as: UTF8.self))\n".utf8))
                continue
            }
            DispatchQueue.main.async { self.onEvent?(ev) }
        }
    }
}
