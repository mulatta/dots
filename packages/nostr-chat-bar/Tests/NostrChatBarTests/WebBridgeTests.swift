import XCTest

@testable import NostrChatBar

final class WebActionDecoderTests: XCTestCase {
    private let id = String(repeating: "ab", count: 32)

    func testDecodesReady() {
        XCTAssertEqual(WebActionDecoder.decode(["type": "ready"]), .ready)
    }

    func testDecodesMessageActions() {
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "reply", "messageId": id]),
            .reply(messageId: id))
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "copy", "messageId": id]),
            .copy(messageId: id))
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "retry", "messageId": id]),
            .retry(messageId: id))
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "cancel", "messageId": id]),
            .cancel(messageId: id))
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "open-image", "messageId": id]),
            .openImage(messageId: id))
    }

    func testDecodesSearchStatus() {
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "search-status", "current": 2, "total": 5]),
            .searchStatus(current: 2, total: 5))
    }

    func testRejectsUnknownType() {
        XCTAssertNil(WebActionDecoder.decode(["type": "exec", "command": "rm"]))
        XCTAssertNil(WebActionDecoder.decode(["type": ""]))
        XCTAssertNil(WebActionDecoder.decode("ready"))
        XCTAssertNil(WebActionDecoder.decode(["messageId": id]))
    }

    func testRejectsMissingOrMalformedMessageIds() {
        XCTAssertNil(WebActionDecoder.decode(["type": "reply"]))
        XCTAssertNil(WebActionDecoder.decode(["type": "reply", "messageId": ""]))
        XCTAssertNil(WebActionDecoder.decode(["type": "reply", "messageId": 42]))
        XCTAssertNil(
            WebActionDecoder.decode(["type": "reply", "messageId": "../../etc/passwd"]))
        XCTAssertNil(
            WebActionDecoder.decode(["type": "reply", "messageId": "a b"]))
        XCTAssertNil(
            WebActionDecoder.decode([
                "type": "reply", "messageId": String(repeating: "a", count: 257),
            ]))
    }

    func testMessageActionsCarryNoPathOrTextFields() {
        // Extra fields must not smuggle content into the action.
        let action = WebActionDecoder.decode([
            "type": "copy", "messageId": id, "text": "attacker text",
            "path": "/etc/passwd",
        ])
        XCTAssertEqual(action, .copy(messageId: id))
    }

    func testOpenLinkAllowsOnlySafeSchemes() {
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "open-link", "url": "https://example.com"]),
            .openLink(url: URL(string: "https://example.com")!))
        XCTAssertEqual(
            WebActionDecoder.decode(["type": "open-link", "url": "nostr:note1abc"]),
            .openLink(url: URL(string: "nostr:note1abc")!))
        XCTAssertNil(WebActionDecoder.decode(["type": "open-link", "url": "javascript:alert(1)"]))
        XCTAssertNil(WebActionDecoder.decode(["type": "open-link", "url": "file:///etc/passwd"]))
        XCTAssertNil(WebActionDecoder.decode(["type": "open-link", "url": "mailto:a@b.c"]))
        XCTAssertNil(WebActionDecoder.decode(["type": "open-link", "url": ""]))
        XCTAssertNil(WebActionDecoder.decode(["type": "open-link"]))
    }

    func testRejectsInvalidSearchStatus() {
        XCTAssertNil(WebActionDecoder.decode(["type": "search-status", "current": -1, "total": 3]))
        XCTAssertNil(WebActionDecoder.decode(["type": "search-status", "current": 4, "total": 3]))
        XCTAssertNil(WebActionDecoder.decode(["type": "search-status", "current": 0]))
    }
}

final class LinkPolicyTests: XCTestCase {
    func testAllowsChatSchemes() {
        for allowed in ["http://x.example", "https://x.example", "nostr:npub1xyz"] {
            XCTAssertTrue(LinkPolicy.allows(URL(string: allowed)!), allowed)
        }
    }

    func testRejectsEverythingElse() {
        for rejected in [
            "javascript:alert(1)", "file:///etc/passwd", "data:text/html,x",
            "mailto:a@b.c", "ftp://x.example",
        ] {
            XCTAssertFalse(LinkPolicy.allows(URL(string: rejected)!), rejected)
        }
    }
}

final class RendererReadyGateTests: XCTestCase {
    func testDropsOperationsBeforeReady() {
        var snapshots = 0
        var ran = 0
        let gate = RendererReadyGate { snapshots += 1 }
        gate.run { ran += 1 }
        XCTAssertEqual(ran, 0)
        XCTAssertEqual(snapshots, 0)
    }

    func testReadySendsSnapshotThenPassesOperations() {
        var snapshots = 0
        var ran = 0
        let gate = RendererReadyGate { snapshots += 1 }
        gate.becomeReady()
        gate.run { ran += 1 }
        XCTAssertEqual(snapshots, 1)
        XCTAssertEqual(ran, 1)
    }

    func testResetDropsOperationsUntilNextReady() {
        var snapshots = 0
        var ran = 0
        let gate = RendererReadyGate { snapshots += 1 }
        gate.becomeReady()
        gate.reset()
        gate.run { ran += 1 }
        XCTAssertEqual(ran, 0)
        gate.becomeReady()
        XCTAssertEqual(snapshots, 2)
        gate.run { ran += 1 }
        XCTAssertEqual(ran, 1)
    }
}

final class RowPayloadTests: XCTestCase {
    private func row(image: String) -> Row {
        Row(
            id: String(repeating: "0", count: 63) + "1", mine: true, text: "hello **md**",
            ts: 1_783_641_600, ack: "✓", image: image, state: "sent", tries: 2,
            replyTo: "")
    }

    func testPayloadNeverContainsLocalPaths() {
        let payload = row(image: "/tmp/media/attachment.png").webPayload
        XCTAssertEqual(payload["hasImage"] as? Bool, true)
        XCTAssertNil(payload["image"])
        for value in payload.values {
            if let string = value as? String {
                XCTAssertFalse(string.contains("/tmp/media"), string)
            }
        }
    }

    func testPayloadCarriesRendererModelFields() {
        let payload = row(image: "").webPayload
        XCTAssertEqual(payload["id"] as? String, String(repeating: "0", count: 63) + "1")
        XCTAssertEqual(payload["mine"] as? Bool, true)
        XCTAssertEqual(payload["text"] as? String, "hello **md**")
        XCTAssertEqual(payload["timestamp"] as? Int64, 1_783_641_600)
        XCTAssertEqual(payload["ack"] as? String, "✓")
        XCTAssertEqual(payload["hasImage"] as? Bool, false)
        XCTAssertEqual(payload["state"] as? String, "sent")
        XCTAssertEqual(payload["tries"] as? Int, 2)
        XCTAssertEqual(payload["error"] as? String, "")
    }

    func testPayloadCarriesRetryError() {
        var failing = row(image: "")
        failing.error = "relay timeout"
        XCTAssertEqual(failing.webPayload["error"] as? String, "relay timeout")
    }

    func testDeliveryActionsRequireUndeliveredOwnMessage() {
        let id = String(repeating: "a", count: 64)
        func candidate(mine: Bool, state: String, tries: Int) -> Row {
            Row(
                id: id, mine: mine, text: "body", ts: 1, ack: "", image: "",
                state: state, tries: tries, replyTo: "")
        }

        XCTAssertTrue(candidate(mine: true, state: "pending", tries: 0).allowsDeliveryAction)
        XCTAssertTrue(candidate(mine: true, state: "sent", tries: 1).allowsDeliveryAction)
        XCTAssertFalse(candidate(mine: true, state: "sent", tries: 0).allowsDeliveryAction)
        XCTAssertFalse(candidate(mine: false, state: "pending", tries: 1).allowsDeliveryAction)
    }

    func testSnapshotPreservesRowOrder() {
        let rows = (1...5).map { index in
            Row(
                id: String(format: "%064d", index), mine: false, text: "m\(index)",
                ts: Int64(index), ack: "", image: "", state: "sent", tries: 0, replyTo: "")
        }
        let snapshot = rows.map(\.webPayload)
        XCTAssertEqual(
            snapshot.compactMap { $0["text"] as? String }, ["m1", "m2", "m3", "m4", "m5"])
    }
}
