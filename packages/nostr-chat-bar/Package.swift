// swift-tools-version:5.9
import PackageDescription
import class Foundation.ProcessInfo

let markdownDependency: Package.Dependency
if let localMarkdown = ProcessInfo.processInfo.environment["NOSTR_CHAT_BAR_SWIFT_MARKDOWN_PATH"] {
    markdownDependency = .package(path: localMarkdown)
} else {
    markdownDependency = .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.6.0")
}

let package = Package(
    name: "nostr-chat-bar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "nostr-chat-bar", targets: ["NostrChatBar"]),
    ],
    dependencies: [
        markdownDependency,
    ],
    targets: [
        .executableTarget(
            name: "NostrChatBar",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/NostrChatBar",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Foundation"),
                .linkedFramework("Network"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("WebKit"),
            ]),
        .testTarget(
            name: "NostrChatBarTests",
            dependencies: ["NostrChatBar"],
            path: "Tests/NostrChatBarTests"),
    ])
