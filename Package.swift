// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Leeway",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LeewayCore", targets: ["LeewayCore"]),
        .executable(name: "leeway", targets: ["leeway"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "LeewayCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "leeway", dependencies: ["LeewayCore"]),
        .testTarget(name: "LeewayCoreTests", dependencies: ["LeewayCore"])
    ]
)
