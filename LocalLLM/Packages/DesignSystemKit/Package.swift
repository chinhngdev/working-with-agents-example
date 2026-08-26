// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystemKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "DesignSystemKit", targets: ["DesignSystemKit"])
    ],
    targets: [
        .target(name: "DesignSystemKit")
    ]
)
