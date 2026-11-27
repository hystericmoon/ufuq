// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UfuqCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UfuqCore", targets: ["UfuqCore"]),
        .executable(name: "ufuq-hook", targets: ["UfuqHook"]),
    ],
    targets: [
        .target(name: "UfuqCore"),
        .executableTarget(name: "UfuqHook", dependencies: ["UfuqCore"]),
        .testTarget(name: "UfuqCoreTests", dependencies: ["UfuqCore"], resources: [.copy("Fixtures")]),
    ]
)
