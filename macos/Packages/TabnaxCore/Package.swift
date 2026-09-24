// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TabnaxCore", platforms: [.macOS(.v15)],
    products: [.library(name: "TabnaxCore", targets: ["TabnaxCore"])],
    targets: [.target(name: "TabnaxCore"), .testTarget(name: "TabnaxCoreTests", dependencies: ["TabnaxCore"])])
