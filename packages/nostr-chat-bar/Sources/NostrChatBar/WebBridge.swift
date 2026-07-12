import Foundation
import WebKit

// MARK: - Web renderer bridge types

// Renderer actions carry IDs or URLs; Swift resolves side effects from canonical state.

enum WebAction: Equatable {
    case ready
    case reply(messageId: String)
    case copy(messageId: String)
    case retry(messageId: String)
    case cancel(messageId: String)
    case openLink(url: URL)
    case openImage(messageId: String)
    case searchStatus(current: Int, total: Int)
}

enum WebActionDecoder {
    static func decode(_ body: Any) -> WebAction? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String
        else { return nil }
        switch type {
        case "ready":
            return .ready
        case "reply":
            return messageId(dict).map { .reply(messageId: $0) }
        case "copy":
            return messageId(dict).map { .copy(messageId: $0) }
        case "retry":
            return messageId(dict).map { .retry(messageId: $0) }
        case "cancel":
            return messageId(dict).map { .cancel(messageId: $0) }
        case "open-image":
            return messageId(dict).map { .openImage(messageId: $0) }
        case "open-link":
            guard let raw = dict["url"] as? String,
                  let url = URL(string: raw),
                  LinkPolicy.allows(url)
            else { return nil }
            return .openLink(url: url)
        case "search-status":
            guard let current = dict["current"] as? Int,
                  let total = dict["total"] as? Int,
                  current >= 0, total >= 0, current <= total
            else { return nil }
            return .searchStatus(current: current, total: total)
        default:
            return nil
        }
    }

    // Canonical-row lookup authorizes IDs; this only keeps bridge input inert.
    static func isValidMessageId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 256 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        }
    }

    private static func messageId(_ dict: [String: Any]) -> String? {
        guard let id = dict["messageId"] as? String, isValidMessageId(id) else { return nil }
        return id
    }
}

enum LinkPolicy {
    static let allowedSchemes: Set<String> = ["http", "https", "nostr"]

    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }
}

// MARK: - Readiness

/// Drops incremental updates until a full snapshot can restore page state.
final class RendererReadyGate {
    private(set) var isReady = false
    var onReady: () -> Void

    init(onReady: @escaping () -> Void = {}) {
        self.onReady = onReady
    }

    /// Runs `op` only when the renderer can receive it.
    func run(_ op: () -> Void) {
        guard isReady else { return }
        op()
    }

    func becomeReady() {
        isReady = true
        onReady()
    }

    func reset() {
        isReady = false
    }
}

// MARK: - Payloads

extension Row {
    var allowsDeliveryAction: Bool {
        mine && (state == "pending" || tries > 0)
    }

    /// The renderer never sees local paths: attachments surface as
    /// `hasImage` and are fetched back by message ID.
    var webPayload: [String: Any] {
        [
            "id": id,
            "mine": mine,
            "text": text,
            "timestamp": ts,
            "ack": ack,
            "hasImage": !image.isEmpty,
            "replyTo": replyTo,
            "state": state,
            "tries": tries,
            "error": error,
        ]
    }
}

// MARK: - Weak message handler

/// WKUserContentController retains its script message handlers; handing
/// it the view directly would create a controller → handler → view →
/// controller cycle.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler? = nil) {
        self.delegate = delegate
    }

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(controller, didReceive: message)
    }
}
