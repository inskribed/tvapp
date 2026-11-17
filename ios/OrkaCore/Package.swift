// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OrkaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OrkaCore", targets: ["OrkaCore"]),
    ],
    targets: [
        .target(name: "OrkaCore"),
        .testTarget(name: "OrkaCoreTests", dependencies: ["OrkaCore"]),
    ]
)
