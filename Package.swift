// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SQLiteReader",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SQLiteReader", targets: ["SQLiteReader"]),
    ],
    targets: [
        // Links the system libsqlite3 automatically via `import SQLite3`.
        .target(name: "SQLiteReader", path: "Sources"),
        .testTarget(name: "SQLiteReaderTests", dependencies: ["SQLiteReader"], path: "Tests"),
    ]
)
