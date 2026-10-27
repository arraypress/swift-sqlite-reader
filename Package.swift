// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-sqlite-reader",
    // SQLite3 is in the OS; nothing is vendored and nothing is fetched.
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(name: "SQLiteReader", targets: ["SQLiteReader"]),
    ],
    targets: [
        .target(name: "SQLiteReader"),
        .testTarget(name: "SQLiteReaderTests", dependencies: ["SQLiteReader"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
