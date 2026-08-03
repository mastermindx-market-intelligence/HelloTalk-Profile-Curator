// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ProfileCurator",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ProfileCuratorCore", targets: ["ProfileCuratorCore"]),
        .executable(name: "ProfileCurator", targets: ["ProfileCuratorApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(
            name: "ProfileCuratorCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "ProfileCuratorApp",
            dependencies: ["ProfileCuratorCore"]
        ),
        .testTarget(
            name: "ProfileCuratorCoreTests",
            dependencies: ["ProfileCuratorCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
