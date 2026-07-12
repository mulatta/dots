import Foundation

// MARK: - Wire types (mirror of daemon/ipc.go)

struct Msg: Codable {
    let id: String
    let pubkey: String?
    let content: String
    let ts: Int64
    let dir: String          // "in" / "out"
    let read: Bool?
    let ack: String?
    let image: String?
    let replyTo: String?
    let state: String?
}

struct Event: Codable {
    let kind: String
    let msg: Msg?
    let target: String?
    let mark: String?
    let image: String?
    let state: String?
    let tries: Int?
    let streaming: Bool?
    let relaysUp: Int?
    let relaysTotal: Int?
    let relays: [String]?
    let pubkey: String?
    let name: String?
    let unread: Int?
    let text: String?
}

// In-memory mirror — the canonical model the web renderer is fed from.
struct Row {
    let id: String
    let mine: Bool
    var text: String
    let ts: Int64
    var ack: String
    var image: String
    var state: String
    var tries: Int
    let replyTo: String
    // Last publish error from the daemon's retry event; cleared on sent.
    var error: String = ""
}
