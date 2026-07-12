import XCTest

@testable import NostrChatBar

final class ChatHistoryViewTests: XCTestCase {
    func testRendererLoadsSnapshotAndRestoresPreReadySearch() throws {
        guard ProcessInfo.processInfo.environment["NOSTR_CHAT_BAR_WEB_ROOT"] != nil else {
            throw XCTSkip("set NOSTR_CHAT_BAR_WEB_ROOT to built renderer assets")
        }

        let snapshotRequested = expectation(description: "renderer requested snapshot")
        let searchReported = expectation(description: "renderer reported restored search")
        let history = ChatHistoryView()
        let id = String(repeating: "a", count: 64)
        history.snapshotProvider = {
            snapshotRequested.fulfill()
            return [
                Row(
                    id: id, mine: false,
                    text: "search needle\n\n```mermaid\ngraph TD\nA --> B\n```", ts: 1,
                    ack: "", image: "", state: "", tries: 0, replyTo: ""
                ).webPayload
            ]
        }
        history.onAction = { action in
            if action == .searchStatus(current: 1, total: 1) {
                searchReported.fulfill()
            }
        }
        history.setSearch(query: "needle")
        history.start()
        wait(for: [snapshotRequested, searchReported], timeout: 10)

        let rendered = expectation(description: "snapshot rendered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            history.webView.evaluateJavaScript(
                "document.querySelectorAll('.bubble-row.search-current').length"
            ) { result, error in
                XCTAssertNil(error)
                XCTAssertEqual(result as? Int, 1)
                rendered.fulfill()
            }
        }
        wait(for: [rendered], timeout: 10)

        let diagram = expectation(description: "dynamic Mermaid chunk rendered")
        history.webView.callAsyncJavaScript(
            """
            return await new Promise(resolve => {
              const deadline = Date.now() + 10000;
              const poll = () => {
                if (document.querySelector('.mermaid-diagram svg')) return resolve(true);
                if (Date.now() >= deadline) return resolve(false);
                setTimeout(poll, 50);
              };
              poll();
            });
            """,
            arguments: [:], in: nil, in: .page
        ) { result in
            switch result {
            case let .success(value): XCTAssertEqual(value as? Bool, true)
            case let .failure(error): XCTFail("Mermaid evaluation failed: \(error)")
            }
            diagram.fulfill()
        }
        wait(for: [diagram], timeout: 12)
        withExtendedLifetime(history) {}
    }
}
