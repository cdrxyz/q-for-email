// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QForEmail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QForEmail", targets: ["QForEmail"])
    ],
    targets: [
        .target(
            name: "QForEmailCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "QForEmail",
            dependencies: ["QForEmailCore"]
        ),
        .testTarget(
            name: "QForEmailTests",
            dependencies: ["QForEmailCore"]
        )
    ]
)
