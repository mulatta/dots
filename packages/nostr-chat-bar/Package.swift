// swift-tools-version:5.7
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
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "nostr-chat-bar", targets: ["nostr-chat-bar"]),
    ],
    dependencies: [
        markdownDependency,
    ],
    targets: [
        .executableTarget(
            name: "nostr-chat-bar",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: ".",
            exclude: [
                "default.nix",
                "NostrChatBar.icns",
                "NoaMenuBarTemplate.png",
            ],
            sources: [
                "BubbleCell.swift",
                "ChatWindowController.swift",
                "ComposeView.swift",
                "Daemon.swift",
                "DropPanel.swift",
                "Extensions.swift",
                "Markdown",
                "Models.swift",
                "main.swift",
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Foundation"),
                .linkedFramework("Network"),
                .linkedFramework("UserNotifications"),
            ]),
    ])
