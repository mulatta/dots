import XCTest

@testable import NostrChatBar

final class ImageDropPolicyTests: XCTestCase {
    func testAcceptsLocalImageFiles() {
        for name in ["shot.png", "photo.JPG", "anim.gif", "pic.jpeg", "modern.webp"] {
            XCTAssertTrue(
                ImageDropPolicy.acceptable(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
    }

    func testRejectsNonImagesAndNonFileURLs() {
        for path in ["/tmp/notes.txt", "/tmp/archive.zip", "/tmp/noext", "/tmp/movie.mp4"] {
            XCTAssertFalse(
                ImageDropPolicy.acceptable(URL(fileURLWithPath: path)), path)
        }
        XCTAssertFalse(ImageDropPolicy.acceptable(URL(string: "https://x.example/a.png")!))
    }
}
