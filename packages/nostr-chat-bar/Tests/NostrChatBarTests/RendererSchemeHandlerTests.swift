import XCTest

@testable import NostrChatBar

final class RendererSchemeHandlerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("renderer-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("<!doctype html>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("console.log(1)".utf8)
            .write(to: root.appendingPathComponent("assets/index.js"))
        try Data("secret".utf8).write(
            to: root.deletingLastPathComponent().appendingPathComponent("outside-secret"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(
            at: root.deletingLastPathComponent().appendingPathComponent("outside-secret"))
    }

    func testResolvesBundleFiles() {
        XCTAssertEqual(
            RendererSchemeHandler.resolve(path: "/index.html", root: root)?.lastPathComponent,
            "index.html")
        XCTAssertEqual(
            RendererSchemeHandler.resolve(path: "/assets/index.js", root: root)?
                .lastPathComponent,
            "index.js")
    }

    func testRejectsTraversalAndOutsidePaths() {
        for hostile in [
            "/../outside-secret",
            "/assets/../../outside-secret",
            "/..%2Foutside-secret",
            "//etc/passwd",
            "/etc/passwd",
            "",
            "/",
        ] {
            XCTAssertNil(RendererSchemeHandler.resolve(path: hostile, root: root), hostile)
        }
    }

    func testRejectsDirectories() {
        XCTAssertNil(RendererSchemeHandler.resolve(path: "/assets", root: root))
    }

    func testMimeTypes() {
        XCTAssertEqual(RendererSchemeHandler.mimeType(forExtension: "html"), "text/html")
        XCTAssertEqual(RendererSchemeHandler.mimeType(forExtension: "js"), "text/javascript")
        XCTAssertEqual(RendererSchemeHandler.mimeType(forExtension: "css"), "text/css")
        XCTAssertEqual(RendererSchemeHandler.mimeType(forExtension: "woff2"), "font/woff2")
        XCTAssertEqual(
            RendererSchemeHandler.mimeType(forExtension: "weird"), "application/octet-stream")
    }
}
