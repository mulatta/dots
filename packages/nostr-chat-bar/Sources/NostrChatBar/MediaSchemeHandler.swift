import Foundation
import UniformTypeIdentifiers
import WebKit

/// Authorizes attachment requests. The URL contributes nothing but a
/// message ID; the file that gets opened always comes from the
/// canonical row, so JavaScript can never name a filesystem path.
enum MediaAuthorizer {
    /// id → attachment file, or nil when the request must be refused:
    /// malformed or unknown IDs, rows without attachments, missing
    /// files, directories, symlinks that leave a regular file behind,
    /// and anything that is not an image.
    static func authorize(id: String, resolvePath: (String) -> String?) -> URL? {
        guard WebActionDecoder.isValidMessageId(id),
              let path = resolvePath(id), !path.isEmpty
        else { return nil }
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              mimeType(for: file)?.hasPrefix("image/") == true
        else { return nil }
        return file
    }

    static func mimeType(for file: URL) -> String? {
        UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
    }
}

/// Serves `nostr-chat-media://message/<message-id>` from the canonical
/// message model.
final class MediaSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "nostr-chat-media"

    /// Looks a message ID up in the canonical rows; returns its local
    /// attachment path or nil.
    var resolvePath: ((String) -> String?)?

    func webView(_: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              url.host == "message",
              url.path.hasPrefix("/"),
              let file = MediaAuthorizer.authorize(
                  id: String(url.path.dropFirst()),
                  resolvePath: { [weak self] id in self?.resolvePath?(id) }),
              let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": MediaAuthorizer.mimeType(for: file) ?? "application/octet-stream",
                "Content-Length": String(data.count),
            ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) {}
}
