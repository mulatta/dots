import Foundation
import WebKit

/// Gives bundled ES modules a non-file origin so WebKit CORS and CSP work.
final class RendererSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "nostr-chat-app"
    static let pageURL = URL(string: "\(scheme)://renderer/index.html")!

    private let root: URL

    init(root: URL) {
        self.root = root
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "json": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "ttf": "font/ttf"
        default: "application/octet-stream"
        }
    }

    static func resolve(url: URL, root: URL) -> URL? {
        guard url.scheme == scheme, url.host == "renderer" else { return nil }
        return resolve(path: url.path, root: root)
    }

    /// Maps a request path onto a regular file under `root`, or nil.
    static func resolve(path: String, root: URL) -> URL? {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !clean.isEmpty,
              !clean.split(separator: "/").contains(".."),
              !clean.contains("//")
        else { return nil }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let target = root.appendingPathComponent(clean)
            .resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(rootPath + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        return target
    }

    func webView(_: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let file = Self.resolve(url: url, root: root),
              let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(forExtension: file.pathExtension),
                "Content-Length": String(data.count),
            ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) {}
}
