// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ClipboardCraft",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ClipboardCraft", targets: ["ClipboardCraft"])
    ],
    targets: [
        .executableTarget(
            name: "ClipboardCraft",
            path: "Sources/ClipboardCraft",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "ClipboardCraftTests",
            dependencies: ["ClipboardCraft"],
            path: "Tests/ClipboardCraftTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
