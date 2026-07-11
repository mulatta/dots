import XCTest

@testable import NostrChatBar

final class MediaAuthorizerTests: XCTestCase {
    private var dir: URL!
    private var image: URL!
    private let knownId = String(repeating: "a", count: 64)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        image = dir.appendingPathComponent("attachment.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func resolver(_ table: [String: String]) -> (String) -> String? {
        { table[$0] }
    }

    func testAuthorizesKnownImageAttachment() {
        let authorized = MediaAuthorizer.authorize(
            id: knownId, resolvePath: resolver([knownId: image.path]))
        XCTAssertEqual(authorized?.lastPathComponent, "attachment.png")
    }

    func testRejectsUnknownAndMalformedIds() {
        let resolve = resolver([knownId: image.path])
        XCTAssertNil(MediaAuthorizer.authorize(id: "b".repeat64, resolvePath: resolve))
        XCTAssertNil(MediaAuthorizer.authorize(id: "../escape", resolvePath: resolve))
        XCTAssertNil(MediaAuthorizer.authorize(id: "", resolvePath: resolve))
    }

    func testRejectsRowsWithoutAttachment() {
        XCTAssertNil(MediaAuthorizer.authorize(id: knownId, resolvePath: resolver([knownId: ""])))
        XCTAssertNil(MediaAuthorizer.authorize(id: knownId, resolvePath: { _ in nil }))
    }

    func testRejectsMissingFilesAndDirectories() {
        XCTAssertNil(
            MediaAuthorizer.authorize(
                id: knownId,
                resolvePath: resolver([knownId: dir.appendingPathComponent("gone.png").path])))
        XCTAssertNil(
            MediaAuthorizer.authorize(id: knownId, resolvePath: resolver([knownId: dir.path])))
    }

    func testRejectsNonImageContent() throws {
        let text = dir.appendingPathComponent("notes.txt")
        try Data("text".utf8).write(to: text)
        XCTAssertNil(
            MediaAuthorizer.authorize(id: knownId, resolvePath: resolver([knownId: text.path])))
        let secret = dir.appendingPathComponent("id_ed25519")
        try Data("key".utf8).write(to: secret)
        XCTAssertNil(
            MediaAuthorizer.authorize(id: knownId, resolvePath: resolver([knownId: secret.path])))
    }

    func testFollowsSymlinksToRegularImagesOnly() throws {
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: image)
        XCTAssertNotNil(
            MediaAuthorizer.authorize(id: knownId, resolvePath: resolver([knownId: link.path])))

        let dirLink = dir.appendingPathComponent("dirlink.png")
        try FileManager.default.createSymbolicLink(at: dirLink, withDestinationURL: dir)
        XCTAssertNil(
            MediaAuthorizer.authorize(id: knownId, resolvePath: resolver([knownId: dirLink.path])))
    }
}

extension String {
    fileprivate var repeat64: String { String(repeating: self, count: 64) }
}
