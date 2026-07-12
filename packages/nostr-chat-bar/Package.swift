// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nostr-chat-bar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "nostr-chat-bar", targets: ["NostrChatBar"]),
    ],
    targets: [
        .executableTarget(
            name: "NostrChatBar",
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
